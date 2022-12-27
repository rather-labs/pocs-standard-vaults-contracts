import { assert, expect } from 'chai';
import { ethers, network } from 'hardhat';

!(network.name === 'hardhat') ? describe.skip : describe('MeatMinter', () => {
  let meatstick, meatMinter, deployer, accounts;
  beforeEach(async () => {
    accounts = await ethers.getSigners();
    deployer = accounts[0];

    const meatstickFactory = await ethers.getContractFactory('Meatstick');
    meatstick = await meatstickFactory.connect(deployer).deploy(deployer.address);

    const meatMinterFactory = await ethers.getContractFactory('MeatMinter');
    meatMinter = await meatMinterFactory.connect(deployer).deploy(meatstick.address);
    await meatstick.changeMinter(meatMinter.address); // We set the allowed minter to the MeatMinter address
  });

  describe('constructor', () => {
    it('sets the initial owner correctly', async () => {
      const response = await meatMinter.getOwner();
      assert.equal(response, deployer.address);
    });

    it('sets the initial Meatstick contract correctly', async () => {
      const response = await meatMinter.getMeatstickContract();
      assert.equal(response, meatstick.address);
    });
  });
  
  describe('role assigning', () => {
    it('changes the contract owner when calling changeOwner with the owner\'s account', async () => {
      const deployerResponse = await meatMinter.getOwner();
      assert.equal(deployerResponse, deployer.address);       
      await meatMinter.changeOwner(accounts[1].address);
      const newOwnerResponse = await meatMinter.getOwner();
      assert.equal(newOwnerResponse, accounts[1].address);
    });

    it('only allows the owner to change the contract\'s owner', async () => {
      const userConnectedMeatMinter = await meatMinter.connect(accounts[1]);
      await expect(userConnectedMeatMinter.changeOwner(accounts[1].address)).to.be.reverted;
      await expect(meatMinter.changeOwner(accounts[1].address)).not.to.be.reverted;
    });
  });
  
  describe('minting', () => {
  
    it('doesn\'t let anyone beside the owner mint tokens', async () => {
      await meatMinter.changeOwner(accounts[3].address); // We set a random address as the owner
      const owner = await meatMinter.getOwner();
      for (let i = 0; i < 6; i++) { // We start at 0 to get the deployer aswell (which is not the owner anymore)
        const userConnectedMeatMinter = await meatMinter.connect(accounts[i]);
        if (owner == accounts[i].address) {
          await expect(userConnectedMeatMinter.safeMint(deployer.address, `account${i}`)).not.to.be.reverted;
        } else {
          await expect(userConnectedMeatMinter.safeMint(deployer.address, `account${i}`)).to.be.reverted;
        }
      }
    });
  
    it('lets the owner mint multiple tokens to an array of addresses', async () => {
      const accounts = await ethers.getSigners();
      const addresses_array: string[] = [];
      const uri_array: string[] = [];
      for (let i = 1; i < 6; i++) {
        addresses_array.push(accounts[i].address);
        uri_array.push(`account${i}`);
      }
      await meatMinter.safeMintArray(addresses_array, uri_array);
  
      for (const address of addresses_array) {
        await expect(await meatstick.balanceOf(address)).to.equal(1); // We check the balance in the meatstick contract
      }
    });
  });
});