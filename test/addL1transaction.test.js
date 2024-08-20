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
    it("Create L2 account", async function() {
      const { sybil } = await loadFixture(deployAndInitializeSybilFixture);
      
      const babyjub = `0x${accounts[0].bjjCompressed}`;
      const fromIdx0 = 0;
      const loadAmountF0 = 0;
      const amountF0 = 0;
      const toIdx0 = 0;

      const initialLastForge = await sybil.nextL1FillingQueue();
      const initialCurrentForge = await sybil.nextL1ToForgeQueue();

      for(let i = 0; i< 121; i++) {
        sybil.addL1Transaction(
          babyjub,
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
      
      sybil.addL1Transaction(
        babyjub,
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
})
