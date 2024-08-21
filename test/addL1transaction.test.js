const {
    loadFixture,
  } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
  const { expect } = require("chai");
  const poseidonUnit = require("circomlib/src/poseidon_gencontract");
  const {
    float40,
    HermezAccount,
    txUtils,
    stateUtils,
    utils,
    feeTable,
    SMTTmpDb,
    Constants,
    RollupDB,
    BatchBuilder,
  } = require("@hermeznetwork/commonjs");
  
const {
  calculateInputMaxTxLevels, deploySybilFixture, deployAndInitializeSybilFixture
} = require("./helpers/helpers");
  
const accounts = [];
for (let i = 0; i < 10; i++) {
  accounts.push(new HermezAccount());
}

describe("Add L1 user transactions", function () {

  describe("Deployment and Initialization", function () {
    it("Should deploy Sybil contract", async function() {
      const {sybil} = await loadFixture(deploySybilFixture);

      expect(sybil != undefined);
    })

    it("Should deploy and initialize Sybil contract", async function() {
        const { sybil, owner } = await loadFixture(deployAndInitializeSybilFixture);
        
        expect(await sybil.owner()).equal(owner);
    })
  })

  describe("L1 Tx Queue", function () {
    it("Queue max length not exceeded", async function() {
      const { sybil } = await loadFixture(deployAndInitializeSybilFixture);
      
      const babyjubjub = `0x${accounts[0].bjjCompressed}`;
      const fromIdx0 = 0;
      const loadAmountF0 = 0;
      const amountF0 = 0;
      const toIdx0 = 0;

      const initialLastForge = await sybil.nextL1FillingQueue();
      const initialCurrentForge = await sybil.nextL1ToForgeQueue();

      for(let i = 0; i < 127; i++) {
        await sybil.addL1Transaction(
          babyjubjub,
          fromIdx0,
          loadAmountF0,
          amountF0,
          toIdx0
        )
      }

      // after 114 l1-user-tx still in the same queue
      const intermidiateLastForge = await sybil.nextL1FillingQueue()
      expect(initialLastForge).to.equal(
        intermidiateLastForge
      );

      const intermidiateCurrentForge = await sybil.nextL1ToForgeQueue()
      expect(initialCurrentForge).to.equal(
        intermidiateCurrentForge
      );
      
      // exceed max tx in queue
      await sybil.addL1Transaction(
        babyjubjub,
        fromIdx0,
        loadAmountF0,
        amountF0,
        toIdx0
      )

      // last Forge is updated at transaction 114
      const after114L1LastForge = await sybil.nextL1FillingQueue();
      const after114L1CurrentForge = await sybil.nextL1ToForgeQueue();
      expect(parseInt(initialLastForge) + 1).to.equal(after114L1LastForge);
      expect(parseInt(initialCurrentForge)).to.equal(after114L1CurrentForge);
    })
  })    

  describe("L1 Tx scenarios", function () {
    it("Create L2 account", async function() {
      const { sybil } = await loadFixture(deployAndInitializeSybilFixture);
      
      const babyjubjub = `0x${accounts[0].bjjCompressed}`;
      const fromIdx0 = 0;
      const loadAmount = 0;
      const amountF0 = 0;
      const toIdx0 = 0;

      expect(await sybil.addL1Transaction(
        babyjubjub,
        fromIdx0,
        loadAmount,
        amountF0,
        toIdx0, 
        {value: 1000}
      )).not.reverted
    })

    it("Create L2 account and deposit", async function() {
      const { sybil } = await loadFixture(deployAndInitializeSybilFixture);
      
      const babyjubjub = `0x${accounts[0].bjjCompressed}`;
      const loadAmount = float40.round(1000);
      const fromIdx0 = 0;
      const amountF0 = 0;
      const toIdx0 = 0;

      expect(await sybil.addL1Transaction(
        babyjubjub,
        fromIdx0,
        loadAmount,
        amountF0,
        toIdx0, 
        {value: 1000}
      )).not.reverted
    })

    it("Create L2 account, deposit and transfer", async function() {
      const { sybil } = await loadFixture(deployAndInitializeSybilFixture);
      
      const babyjubjub = `0x${accounts[0].bjjCompressed}`;
      const loadAmount = float40.round(1000);
      const fromIdx0 = 0;
      const amountF0 = 0;
      const toIdx = await sybil.lastIdx() + 1n;

      // TODO: generate valid toIdx
      await expect(sybil.addL1Transaction(
        babyjubjub,
        fromIdx0,
        loadAmount,
        amountF0,
        toIdx, 
        {value: 1000}
      )).to.revertedWith("Sybil::_addL1Transaction: INVALID_TOIDX")
    })
  })
})
