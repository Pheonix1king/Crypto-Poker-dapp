// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title PokerEscrow
 * @notice Holds table funds, enforces buy-ins/antes, verifies signed settlements, pays winners.
 *         Gameplay (cards/bets) is off-chain. This contract focuses on funds safety and fairness.
 */
contract PokerEscrow is Ownable, ReentrancyGuard {
    using ECDSA for bytes32;

    struct Table {
        address token;            // address(0) for native coin (ETH/BNB/MATIC/etc)
        uint256 minBuyIn;
        uint256 maxBuyIn;
        uint256 rakeBps;          // e.g., 250 = 2.5%
        uint256 rakeCap;          // max rake per settlement (in wei/token units)
        address rakeCollector;    // house wallet
        bool open;
    }

    struct SeatBalance {
        uint256 amount;           // escrowed balance per player per table
    }

    // tableId => Table
    mapping(bytes32 => Table) public tables;

    // tableId => player => SeatBalance
    mapping(bytes32 => mapping(address => SeatBalance)) public balances;

    // anti-replay: record used settlement digests
    mapping(bytes32 => bool) public usedSettlement;

    event TableCreated(bytes32 indexed tableId, address token, uint256 minBuyIn, uint256 maxBuyIn, uint256 rakeBps, uint256 rakeCap, address rakeCollector);
    event TableOpen(bytes32 indexed tableId, bool open);
    event BuyIn(bytes32 indexed tableId, address indexed player, uint256 amount);
    event CashOut(bytes32 indexed tableId, address indexed player, uint256 amount);
    event Settled(bytes32 indexed tableId, bytes32 indexed settlementId, address[] recipients, uint256[] amounts, uint256 rakeTaken);

    error TableClosed();
    error InvalidRange();
    error InvalidAmount();
    error NotEnough();
    error AlreadyUsed();
    error BadSig();

    // -------- Admin: create/manage tables --------

    function createTable(
        bytes32 tableId,
        address token,
        uint256 minBuyIn,
        uint256 maxBuyIn,
        uint256 rakeBps,
        uint256 rakeCap,
        address rakeCollector
    ) external onlyOwner {
        if (minBuyIn == 0 || maxBuyIn < minBuyIn) revert InvalidRange();
        tables[tableId] = Table({
            token: token,
            minBuyIn: minBuyIn,
            maxBuyIn: maxBuyIn,
            rakeBps: rakeBps,
            rakeCap: rakeCap,
            rakeCollector: rakeCollector,
            open: true
        });
        emit TableCreated(tableId, token, minBuyIn, maxBuyIn, rakeBps, rakeCap, rakeCollector);
    }

    function setOpen(bytes32 tableId, bool open_) external onlyOwner {
        tables[tableId].open = open_;
        emit TableOpen(tableId, open_);
    }

    // -------- Player flows --------

    // Native coin only in this starter. For ERC20, add approve/transferFrom flows.
    function buyIn(bytes32 tableId) external payable nonReentrant {
        Table memory t = tables[tableId];
        if (!t.open) revert TableClosed();
        if (t.token != address(0)) revert InvalidAmount(); // this starter supports native only
        if (msg.value < t.minBuyIn || msg.value > t.maxBuyIn) revert InvalidAmount();
        balances[tableId][msg.sender].amount += msg.value;
        emit BuyIn(tableId, msg.sender, msg.value);
    }

    function cashOut(bytes32 tableId, uint256 amount) external nonReentrant {
        SeatBalance storage s = balances[tableId][msg.sender];
        if (s.amount < amount) revert NotEnough();
        s.amount -= amount;
        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        require(ok, "withdraw failed");
        emit CashOut(tableId, msg.sender, amount);
    }

    /**
     * @dev Settle a finished hand or session using multi-signed payouts.
     *
     * @param tableId - the table
     * @param settlementId - unique id for this settlement (use keccak of handNo + rnd)
     * @param recipients - payout receivers (players and optionally house rake)
     * @param amounts - amounts per recipient (native units)
     * @param signers - addresses that must have signed (e.g., both players, optional house)
     * @param sigs - signatures over the typed hash from each signer in same order
     */
    function settle(
        bytes32 tableId,
        bytes32 settlementId,
        address[] calldata recipients,
        uint256[] calldata amounts,
        address[] calldata signers,
        bytes[] calldata sigs
    ) external nonReentrant {
        if (usedSettlement[settlementId]) revert AlreadyUsed();
        if (recipients.length != amounts.length) revert InvalidRange();
        if (signers.length != sigs.length) revert InvalidRange();

        // Build digest: domain separation keeps signatures specific to this contract & chain
        bytes32 digest = keccak256(
            abi.encode(
                keccak256("PokerSettlement(bytes32 tableId,bytes32 settlementId,address[] recipients,uint256[] amounts,uint256 chainId,address contract)") ,
                tableId,
                settlementId,
                keccak256(abi.encodePacked(recipients)),
                keccak256(abi.encodePacked(amounts)),
                block.chainid,
                address(this)
            )
        ).toEthSignedMessageHash();

        for (uint256 i = 0; i < signers.length; i++) {
            address recovered = digest.recover(sigs[i]);
            if (recovered != signers[i]) revert BadSig();
        }

        usedSettlement[settlementId] = true;

        // Compute total debit against table balances
        uint256 total;
        for (uint256 i = 0; i < recipients.length; i++) {
            total += amounts[i];
        }

        // In this minimal version we debit evenly from all seated signers.
        // In production you'd track per-hand committed amounts. Here, require each signer has enough.
        uint256 share = total / signers.length;
        for (uint256 i = 0; i < signers.length; i++) {
            SeatBalance storage s = balances[tableId][signers[i]];
            if (s.amount < share) revert NotEnough();
            s.amount -= share;
        }

        // Optional rake (off-chain you include this as a recipient). For clarity we *also* enforce global caps here.
        uint256 rakeTaken = 0;
        Table memory t = tables[tableId];
        if (t.rakeCollector != address(0) && t.rakeBps > 0 && total > 0) {
            uint256 theoretical = (total * t.rakeBps) / 10_000;
            rakeTaken = theoretical > t.rakeCap ? t.rakeCap : theoretical;
        }

        // Payouts + rake
        uint256 remaining = total;
        for (uint256 i = 0; i < recipients.length; i++) {
            uint256 amt = amounts[i];
            remaining -= amt;
            (bool ok, ) = payable(recipients[i]).call{value: amt}("");
            require(ok, "pay failed");
        }

        if (rakeTaken > 0) {
            (bool ok2, ) = payable(t.rakeCollector).call{value: rakeTaken}("");
            require(ok2, "rake failed");
        }

        emit Settled(tableId, settlementId, recipients, amounts, rakeTaken);
    }

    // Emergency owner sweep (of dust) – production: use a more robust treasury model
    function sweep(address to) external onlyOwner {
        (bool ok, ) = payable(to).call{value: address(this).balance}("");
        require(ok, "sweep failed");
    }
}