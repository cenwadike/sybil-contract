const {
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { expect } = require("chai");
const poseidonUnit = require("circomlib/src/poseidon_gencontract");

const {
  calculateInputMaxTxLevels, deploySybilFixture
} = require("./helpers/helpers");

describe("Sybil deployment", function () {
  it("Should deploy Sybil contract", async function() {
    await loadFixture(deploySybilFixture);
  }) 
  
  it("Should initialize Sybil contract", async function() {
    const {sybil, owner} = await loadFixture(deploySybilFixture);

    const VerifierRollupHelper = await ethers.getContractFactory(
      "VerifierRollupHelper"
    );
    const hardhatVerifierRollupHelper = await  VerifierRollupHelper.deploy();
    const hardhatVerifierRollupAddr = await hardhatVerifierRollupHelper.getAddress();

    const Poseidon2Elements = new ethers.ContractFactory(
      poseidonUnit.generateABI(2),
      poseidonUnit.createCode(2),
      owner
    );

    const Poseidon3Elements = new ethers.ContractFactory(
      poseidonUnit.generateABI(3),
      poseidonUnit.createCode(3),
      owner
    );

    const Poseidon4Elements = new ethers.ContractFactory(
      poseidonUnit.generateABI(4),
      poseidonUnit.createCode(4),
      owner
    );

    const hardhatPoseidon2Elements = await Poseidon2Elements.deploy();
    const hardhatPoseidon3Elements = await Poseidon3Elements.deploy();
    const hardhatPoseidon4Elements = await Poseidon4Elements.deploy();
    
    const poseidonAddr2 = await hardhatPoseidon2Elements.getAddress();
    const poseidonAddr3 = await hardhatPoseidon3Elements.getAddress();
    const poseidonAddr4 = await hardhatPoseidon4Elements.getAddress();

    const forgeL1L2BatchTimeout = 10;
    const maxTx = 512;
    const nLevels = 32;
    
    await sybil.connect(owner).initialize(
      [hardhatVerifierRollupAddr],
      calculateInputMaxTxLevels([maxTx], [nLevels]), 
      forgeL1L2BatchTimeout,
      poseidonAddr2,
      poseidonAddr3,
      poseidonAddr4
    );
  });

  it("Should not initialize contract more than once", async function() {
    const {sybil, owner} = await loadFixture(deploySybilFixture);

    const VerifierRollupHelper = await ethers.getContractFactory(
      "VerifierRollupHelper"
    );
    const hardhatVerifierRollupHelper = await  VerifierRollupHelper.deploy();
    const hardhatVerifierRollupAddr = await hardhatVerifierRollupHelper.getAddress();

    const Poseidon2Elements = new ethers.ContractFactory(
      poseidonUnit.generateABI(2),
      poseidonUnit.createCode(2),
      owner
    );

    const Poseidon3Elements = new ethers.ContractFactory(
      poseidonUnit.generateABI(3),
      poseidonUnit.createCode(3),
      owner
    );

    const Poseidon4Elements = new ethers.ContractFactory(
      poseidonUnit.generateABI(4),
      poseidonUnit.createCode(4),
      owner
    );

    const hardhatPoseidon2Elements = await Poseidon2Elements.deploy();
    const hardhatPoseidon3Elements = await Poseidon3Elements.deploy();
    const hardhatPoseidon4Elements = await Poseidon4Elements.deploy();
    
    const poseidonAddr2 = await hardhatPoseidon2Elements.getAddress();
    const poseidonAddr3 = await hardhatPoseidon3Elements.getAddress();
    const poseidonAddr4 = await hardhatPoseidon4Elements.getAddress();

    const forgeL1L2BatchTimeout = 10;
    const maxTx = 512;
    const nLevels = 32;
    
    await sybil.connect(owner).initialize(
      [hardhatVerifierRollupAddr],
      calculateInputMaxTxLevels([maxTx], [nLevels]), 
      forgeL1L2BatchTimeout,
      poseidonAddr2,
      poseidonAddr3,
      poseidonAddr4
    );

    await expect(sybil.connect(owner).initialize(
      [hardhatVerifierRollupAddr],
      calculateInputMaxTxLevels([maxTx], [nLevels]), 
      forgeL1L2BatchTimeout,
      poseidonAddr2,
      poseidonAddr3,
      poseidonAddr4
    )).to.be.revertedWithCustomError(sybil, "InvalidInitialization()");
  });
  
  it("Should emit event after initialization", async function() {
    const {sybil, owner} = await loadFixture(deploySybilFixture);

    const VerifierRollupHelper = await ethers.getContractFactory(
      "VerifierRollupHelper"
    );
    const hardhatVerifierRollupHelper = await  VerifierRollupHelper.deploy();
    const hardhatVerifierRollupAddr = await hardhatVerifierRollupHelper.getAddress();

    const Poseidon2Elements = new ethers.ContractFactory(
      poseidonUnit.generateABI(2),
      poseidonUnit.createCode(2),
      owner
    );

    const Poseidon3Elements = new ethers.ContractFactory(
      poseidonUnit.generateABI(3),
      poseidonUnit.createCode(3),
      owner
    );

    const Poseidon4Elements = new ethers.ContractFactory(
      poseidonUnit.generateABI(4),
      poseidonUnit.createCode(4),
      owner
    );

    const hardhatPoseidon2Elements = await Poseidon2Elements.deploy();
    const hardhatPoseidon3Elements = await Poseidon3Elements.deploy();
    const hardhatPoseidon4Elements = await Poseidon4Elements.deploy();
    
    const poseidonAddr2 = await hardhatPoseidon2Elements.getAddress();
    const poseidonAddr3 = await hardhatPoseidon3Elements.getAddress();
    const poseidonAddr4 = await hardhatPoseidon4Elements.getAddress();

    const forgeL1L2BatchTimeout = 10;
    const maxTx = 512;
    const nLevels = 32;
    
    await sybil.connect(owner).initialize(
      [hardhatVerifierRollupAddr],
      calculateInputMaxTxLevels([maxTx], [nLevels]), 
      forgeL1L2BatchTimeout,
      poseidonAddr2,
      poseidonAddr3,
      poseidonAddr4
    );

    expect(await sybil.owner()).equal(owner.address);
  });

  it("Should initialize contract with correct owner", async function() {
    const {sybil, owner} = await loadFixture(deploySybilFixture);

    const VerifierRollupHelper = await ethers.getContractFactory(
      "VerifierRollupHelper"
    );
    const hardhatVerifierRollupHelper = await  VerifierRollupHelper.deploy();
    const hardhatVerifierRollupAddr = await hardhatVerifierRollupHelper.getAddress();

    const Poseidon2Elements = new ethers.ContractFactory(
      poseidonUnit.generateABI(2),
      poseidonUnit.createCode(2),
      owner
    );

    const Poseidon3Elements = new ethers.ContractFactory(
      poseidonUnit.generateABI(3),
      poseidonUnit.createCode(3),
      owner
    );

    const Poseidon4Elements = new ethers.ContractFactory(
      poseidonUnit.generateABI(4),
      poseidonUnit.createCode(4),
      owner
    );

    const hardhatPoseidon2Elements = await Poseidon2Elements.deploy();
    const hardhatPoseidon3Elements = await Poseidon3Elements.deploy();
    const hardhatPoseidon4Elements = await Poseidon4Elements.deploy();
    
    const poseidonAddr2 = await hardhatPoseidon2Elements.getAddress();
    const poseidonAddr3 = await hardhatPoseidon3Elements.getAddress();
    const poseidonAddr4 = await hardhatPoseidon4Elements.getAddress();

    const forgeL1L2BatchTimeout = 10;
    const maxTx = 512;
    const nLevels = 32;
    
    await expect(sybil.connect(owner).initialize(
      [hardhatVerifierRollupAddr],
      calculateInputMaxTxLevels([maxTx], [nLevels]), 
      forgeL1L2BatchTimeout,
      poseidonAddr2,
      poseidonAddr3,
      poseidonAddr4
    )).to.emit(sybil, "InitializeSybilEvent").withArgs(forgeL1L2BatchTimeout);

    expect(await sybil.owner()).equal(owner);
  });
});
