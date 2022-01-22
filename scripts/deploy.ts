// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import hre from 'hardhat';

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  const initiationAddress = '0x08aea8158856cdd97e0cc976f4681d40d34447d0'
  const initiationBuyback = '0x08aea8158856cdd97e0cc976f4681d40d34447d0'
  const pinkAntiBot = '0x8efdb3b642eb2a20607ffe0a56cfeff6a95df002'

  const MicroPets = await hre.ethers.getContractFactory("MicroPets");

  const microPets = await MicroPets.deploy(initiationAddress, initiationBuyback, pinkAntiBot);

  console.log(microPets)

  await microPets.deployed();

  console.log("MicroPets deployed to:", microPets.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
