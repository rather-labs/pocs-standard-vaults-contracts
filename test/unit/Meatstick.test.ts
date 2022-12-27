import { assert, expect } from 'chai';
import { ethers, network } from 'hardhat';

!(network.name === 'hardhat') ? describe.skip : describe('Meatstick', () => {
  let meatstick, deployer, accounts;
  beforeEach(async () => {
    accounts = await ethers.getSigners();
    deployer = accounts[0];

    const meatstickFactory = await ethers.getContractFactory('Meatstick');
    meatstick = await meatstickFactory.connect(deployer).deploy(deployer.address);
  });

  describe('constructor', () => {
    it('sets the initial URI correctly', async () => {
      const response = await meatstick.getBaseURI();
      assert.equal(response, 'https://bucket-name.s3.region-code.amazonaws.com/');
    });

    it('sets the initial owner correctly', async () => {
      const response = await meatstick.getOwner();
      assert.equal(response, deployer.address);
    });

    it('sets the initial minter correctly', async () => {
      const response = await meatstick.getMinter();
      assert.equal(response, deployer.address);
    });
  });
  
  describe('role assigning', () => {
    it('allows the owner to change the contract\'s owner', async () => {
      const deployerResponse = await meatstick.getOwner();
      assert.equal(deployerResponse, deployer.address);       
      await meatstick.changeOwner(accounts[1].address);
      const newOwnerResponse = await meatstick.getOwner();
      assert.equal(newOwnerResponse, accounts[1].address);
    });

    it('allows the owner to change the allowed minter', async () => {
      const deployerResponse = await meatstick.getMinter();
      assert.equal(deployerResponse, deployer.address);       
      await meatstick.changeMinter(accounts[1].address);
      const newOwnerResponse = await meatstick.getMinter();
      assert.equal(newOwnerResponse, accounts[1].address);
    });

    it('only allows the owner to change any role', async () => {
      const userConnectedMeatstick = await meatstick.connect(accounts[1]);
      await expect(userConnectedMeatstick.changeMinter(accounts[1].address)).to.be.reverted;
      await expect(userConnectedMeatstick.changeOwner(accounts[1].address)).to.be.reverted;

      await expect(meatstick.changeMinter(accounts[1].address)).not.to.be.reverted;
      await expect(meatstick.changeOwner(accounts[1].address)).not.to.be.reverted;
    });
  });
  
  describe('minting', () => {
  
    it('doesn\'t let anyone beside the allowed minter mint tokens', async () => {
      await meatstick.changeMinter(accounts[3].address); // We set a random address as the allowed minter

      for (let i = 0; i < 6; i++) { // We start at 0 to get the deployer aswell (which is not the allowed minter anymore)
        const userRatherLabsDNA = await meatstick.connect(accounts[i]);
        if (await meatstick.getMinter() == accounts[i].address) {
          await expect(userRatherLabsDNA.safeMint(deployer.address, `account${i}`)).not.to.be.reverted;
        } else {
          await expect(userRatherLabsDNA.safeMint(deployer.address, `account${i}`)).to.be.reverted;
        }
      }
    });
  
    it('lets the allowed minter mint multiple tokens to an array of addresses', async () => {
      const accounts = await ethers.getSigners();
      const addresses_array: string[] = [];
      const uri_array: string[] = [];
      for (let i = 1; i < 6; i++) {
        addresses_array.push(accounts[i].address);
        uri_array.push(`account${i}`);
      }
      await meatstick.mintArray(addresses_array, uri_array);
  
      for (const address of addresses_array) {
        await expect(await meatstick.balanceOf(address)).to.equal(1);
      }
    });
  
    it('increments token ID after minting', async () => {
      const accounts = await ethers.getSigners();
      await expect(await meatstick.getCurrentTokenId()).to.equal(0);
      await meatstick.safeMint(accounts[0].address, `account${0}`);
      await expect(await meatstick.getCurrentTokenId()).to.equal(1);
    });
  
  });
  
  /* describe('transfer', () => {
      it('doesn\'t let anyone transfer tokens', async () => {
        await meatstick.addAdmin(accounts[3].address); // We add a random admin
        for (let i = 0; i < 6; i++) { // We start at 0 to get the deployer aswell
          await meatstick.safeMint(accounts[i].address, `account${i}`); // We mint a token to the current user
          const userMeatstick = await meatstick.connect(accounts[i]); // Then we connect the current user to the contract
          await expect(userMeatstick.transferFrom(accounts[i].address, deployer.address, i)).to.be.reverted; // And we try to transfer it
        }
      });
    }); */
  
  describe('burning', () => {
    it('only allow owners to burn their own tokens', async () => {
      await meatstick.safeMint(deployer.address, 'deployer'); // We mint a token to the deployer to try and burn
      for (let i = 1; i < 6; i++) {
        const userMeatstick = await meatstick.connect(accounts[i]);
        await expect(userMeatstick.burnTokenByOwner(0)).to.be.reverted; 
      }
      await expect(meatstick.burnTokenByOwner(0)).not.to.be.reverted;
    });
  
    it('allows the owner to burn any token', async () => {
      for (let i = 0; i < 6; i++) {
        await meatstick.safeMint(accounts[i].address, `account${i}`);
        await expect(meatstick.burnToken(i)).not.to.be.reverted; 
      }
    });
  
    it('does not allow a non-admin to burn any token', async () => {
      await meatstick.safeMint(accounts[3].address, `account${3}`);
      for (let i = 1; i < 6; i++) { // We purposely avoid accounts[0] because that's the owner
        const userMeatstick = await meatstick.connect(accounts[i]);
        await expect(userMeatstick.burnToken(3)).to.be.reverted; 
      }
    });
  });
  
  describe('base URI', () => {
    it('changes the base URI when called by the owner', async () => {
      await expect(await meatstick.getBaseURI()).to.equal('https://bucket-name.s3.region-code.amazonaws.com/');
      await meatstick.changeBaseURI('adminChangedThis');
      await expect(await meatstick.getBaseURI()).to.equal('adminChangedThis');
    });
  
    it('only allow the owner to change the base URI', async () => {
      await expect(meatstick.changeBaseURI('ownerChangedThis')).not.to.be.reverted;
      for (let i = 1; i < 6; i++) { // We purposly avoid accounts[0] as that's the owner
        const userConnectedMeatstick = await meatstick.connect(accounts[i]);
        await expect(userConnectedMeatstick.changeBaseURI('nonOwnerChangedThis')).to.be.reverted; 
      }
    });
  });
});
