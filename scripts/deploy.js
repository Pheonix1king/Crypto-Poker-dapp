const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying with:", deployer.address);

  const PokerEscrow = await hre.ethers.getContractFactory("PokerEscrow");
  const contract = await PokerEscrow.deploy("0xPLAYER2_WALLET_ADDRESS", { value: hre.ethers.parseEther("0.1") });

  await contract.waitForDeployment();
  console.log("PokerEscrow deployed to:", await contract.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});