// scripts/deploy.js
const { ethers, upgrades } = require("hardhat");
const chalk = require("chalk");
const BigNumber = require("bignumber.js");

const fs = require("fs");
async function main() {
  async function getRaceInfo() {
    let currentRace = await NFTRace.currentRace();
    let raceInfo = await NFTRace.getRaceInfo(currentRace);
    console.log(
      "Current race #" +
        raceInfo._raceNumber.toString() +
        " with " +
        raceInfo._participantsCount.toString() +
        " participants"
    );
  }

  // this is to test based on tutorial in case
  // const Box = await ethers.getContractFactory("Box");
  // console.log("Deploying Box...");
  // const box = await upgrades.deployProxy(Box, [42], { initializer: "store" });
  // console.log("Box deployed to:", box.address);
  // await box.store(420);
  // const retrieve = await box.retrieve();
  // console.log("retrieve", retrieve.toString());

  const NiftyAddons = await deploy("NiftyAddons", [
    "https://gallery.verynifty.io/api/addon/",
  ]);
  const MuseToken = await deploy("MuseToken");

  const NFT1 = await deploy("VNFT", [MuseToken.address]);
  const NFT2 = await deploy("VNFT", [MuseToken.address]);
  const NFT3 = await deploy("VNFT", [MuseToken.address]);

  MuseToken.mint(
    "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
    "100000000000000000000"
  );

  const NFTRace = await deploy("NFTRaceMuse", [
    NFT1.address,
    MuseToken.address,
  ]);

  await NFT1.grantRole(
    "0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6",
    "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266"
  );
  await NFT1.grantRole(
    "0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6",
    NFTRace.address
  );
  await NFT2.grantRole(
    "0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6",
    "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266"
  );
  await NFT3.grantRole(
    "0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6",
    "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266"
  );

  await NFT1.mint("0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266");
  await NFT1.mint("0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266");
  await NFT1.mint("0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266");
  await NFT2.mint("0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266");
  await NFT2.mint("0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266");
  await NFT2.mint("0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266");
  await NFT3.mint("0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266");
  await NFT3.mint("0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266");
  await NFT3.mint("0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266");
  await NFT3.mint("0x1111111111111111111111111111111111111111");

  let entryPrice = "100000000000000000"; // 0.1 ether
  entryPrice = "100000000000000000";
  let raceTime = 60 * 25; // 25 minutes
  let devAddress = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"; // the address that will receive the fees
  await ethers.provider.send("evm_increaseTime", [60]); // add minute

  await NFTRace.setRaceParameters(entryPrice, raceTime, 10);

  await NFTRace.on(
    "participantEntered",
    function (currentRace, betSize, participant, tokenAddress, tokenId) {
      console.log(
        participant +
          " Joined the race " +
          currentRace.toString() +
          " with NFT: " +
          tokenAddress +
          "::" +
          tokenId.toString()
      );
    }
  );

  await NFTRace.on("raceEnded", function (currentRace, prize, winner) {
    console.log(
      winner +
        " won " +
        prize.toString() +
        " at the race " +
        currentRace.toString()
    );
  });

  /* At this point everything is deployed and the owner has 3 NFT of each */

  // await getRaceInfo()

  // approve muse for spending
  await MuseToken.approve(
    NFTRace.address,
    "1000000000000000000000000000000000000000"
  );

  console.log(
    (
      await MuseToken.balanceOf("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266")
    ).toString()
  );

  while (true) {
    await NFTRace.joinRace(NFT1.address, 0, 721);

    await NFTRace.joinRace(NFT1.address, 1, 721);
    await NFTRace.joinRace(NFT1.address, 2, 721);
    await NFTRace.joinRace(NFT2.address, 0, 721);
    await new Promise((r) => setTimeout(r, 10000));
    await getRaceInfo();

    await NFTRace.joinRace(NFT3.address, 1, 721);
    await NFTRace.joinRace(NFT3.address, 2, 721);

    console.log("Total NFT Supply" + (await NFT1.totalSupply()).toString());
    console.log(
      (
        await MuseToken.balanceOf("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266")
      ).toString()
    );

    console.log((await MuseToken.totalSupply()).toString());
  }

  await getRaceInfo();
}

async function deploy(name, _args) {
  const args = _args || [];

  console.log(`📄 ${name}`);
  const contractArtifacts = await ethers.getContractFactory(name);
  const contract = await contractArtifacts.deploy(...args);
  console.log(
    chalk.cyan(name),
    "deployed to:",
    chalk.magenta(contract.address)
  );
  // fs.writeFileSync(`artifacts/${name}.address`, contract.address);
  console.log("\n");
  return contract;
}

main();
