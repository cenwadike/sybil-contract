const {
    loadFixture,
  } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
  const { expect } = require("chai");
  const {
    HermezAccount,
  } = require("@hermeznetwork/commonjs");
  
const {
  deploySybilFixture, deployAndInitializeSybilFixture
} = require("./helpers/helpers");

  
const accounts = [];
for (let i = 0; i < 10; i++) {
  accounts.push(new HermezAccount());
}

describe("Forge L1 and L2 transactions", function () {

  describe("Deployment and Initialization", function () {
    it("Should deploy Sybil contract", async function() {
      const {sybil} = await loadFixture(deploySybilFixture);

      expect(sybil != undefined);
    })

    it("Should deploy and initialize Sybil contract", async function() {
     await loadFixture(deployAndInitializeSybilFixture);
    })
  })

  describe("Forge Batch", function () {
    it("Clear Filling Queue ", async function() {
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

      // after 128 l1-user-tx still in the same queue
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

      // last Forge is updated at transaction 128
      const after128L1LastForge = await sybil.nextL1FillingQueue();
      const after128L1CurrentForge = await sybil.nextL1ToForgeQueue();
      expect(parseInt(initialLastForge) + 1).to.equal(after128L1LastForge);
      expect(parseInt(initialCurrentForge)).to.equal(after128L1CurrentForge);

      // forge batch
      await sybil.forgeBatch(
        newLastIdx = 256,
        newStRoot = 256,
        newExitRoot = 256,
        encodedL1CoordinatorTx = "0x00",
        l1L2TxsData = "0x00",
        feeIdxCoordinator = "0x00",
        verifierIdx = 0,
        l1Batch = true,
        proofA = ["0", "0"],
        proofB = [
          ["0", "0"],
          ["0", "0"],
        ],
        proofC = ["0", "0"],
      )

      // check next queue is used to queue L1 transactions
      const afterForgeL1LastForge = await sybil.nextL1FillingQueue();
      expect(parseInt(initialLastForge) + 2).to.equal(afterForgeL1LastForge);
    })
    it("Current Queue is updated", async function() {
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

      // after 128 l1-user-tx still in the same queue
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

      // last Forge is updated at transaction 128
      const after128L1LastForge = await sybil.nextL1FillingQueue();
      const after128L1CurrentForge = await sybil.nextL1ToForgeQueue();
      expect(parseInt(initialLastForge) + 1).to.equal(after128L1LastForge);
      expect(parseInt(initialCurrentForge)).to.equal(after128L1CurrentForge);

      // forge batch
      await sybil.forgeBatch(
        newLastIdx = 256,
        newStRoot = 256,
        newExitRoot = 256,
        encodedL1CoordinatorTx = "0x00",
        l1L2TxsData = "0x00",
        feeIdxCoordinator = "0x00",
        verifierIdx = 0,
        l1Batch = true,
        proofA = ["0", "0"],
        proofB = [
          ["0", "0"],
          ["0", "0"],
        ],
        proofC = ["0", "0"],
      )

      // check queue is cleared
      const afterforgeL1CurrentForge = await sybil.nextL1ToForgeQueue();
      expect(parseInt(initialCurrentForge + 1n)).to.equal(afterforgeL1CurrentForge);
    })
  })    
})