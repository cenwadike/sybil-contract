const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { keccak256 } = require("ethers");
const poseidonUnit = require("circomlib/src/poseidon_gencontract");

const {
  calculateInputMaxTxLevels
} = require("./helpers/helpers");

describe("Sybil", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deploySybilFixture() {
    const [owner] = await ethers.getSigners();

    const Sybil = await ethers.getContractFactory("Sybil");
    const sybil = await Sybil.deploy();
    contractAddress = await sybil.getAddress();

    return { sybil, owner, contractAddress };
  }

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
    }) 
  });
});
