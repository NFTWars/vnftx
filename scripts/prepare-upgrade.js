// scripts/prepare_upgrade.js
const { ethers, upgrades } = require("hardhat");

async function main() {
  const proxyAddress = "0xb7278a61aa25c888815afc32ad3cc52ff24fe575";

  // leaving this as was the tutorial i did, in case questions arise.
  // const BoxV2 = await ethers.getContractFactory("BoxV2");
  // console.log("Preparing upgrade...");
  // const boxV2Address = await upgrades.prepareUpgrade(proxyAddress, BoxV2);
  // console.log("BoxV2 at:", boxV2Address);

  const VNFTxV2 = await ethers.getContractFactory("VNFTxV2");
  console.log("Preparing upgrade...");
  const vnftxV2Address = await upgrades.prepareUpgrade(proxyAddress, VNFTxV2, {
    initializer: "initialize",
    unsafeAllowCustomTypes: true,
  });
  console.log("VNFTxV2 at:", vnftxV2Address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
