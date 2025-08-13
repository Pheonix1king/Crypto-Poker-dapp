const { expect } = require("chai");

describe("PokerEscrow", function () {
  it("Should allow two players to bet and declare winner", async function () {
    const [player1, player2] = await ethers.getSigners();

    const PokerEscrow = await ethers.getContractFactory("PokerEscrow");
    const poker = await PokerEscrow.connect(player1).deploy(player2.address, { value: ethers.parseEther("0.1") });

    await poker.connect(player2).joinGame({ value: ethers.parseEther("0.1") });
    await poker.connect(player1).declareWinner(player1.address);

    expect(await ethers.provider.getBalance(poker.target)).to.equal(0);
  });
});
