const {
    loadFixture,
  } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { expect } = require("chai");
const {
    float40,
    HermezAccount,
    RollupDB
} = require("@hermeznetwork/commonjs");

const SMTMemDB = require("circomlib").SMTMemDB;

const {
  deploySybilFixture, deployAndInitializeSybilFixture,
  ForgerTest,
  l1UserTxCreateAccountDeposit
} = require("./helpers/helpers");
  
const accounts = [];
for (let i = 0; i < 10; i++) {
  accounts.push(new HermezAccount());
}

describe("Test Withdraw With Merkle Proof", function () {
    describe("Deployment and Initialization", function () {
        it("Should deploy Sybil contract", async function() {
          const {sybil} = await loadFixture(deploySybilFixture);
    
          expect(sybil != undefined);
        })
    
        it("Should deploy and initialize Sybil contract", async function() {
          await loadFixture(deployAndInitializeSybilFixture);
        })
    })

    describe("Create L1 deposit transaction and withdraw", function () {
        it("Create L1 deposit transaction and withdraw", async function() {
            const { sybil, owner } = await loadFixture(deployAndInitializeSybilFixture);
            
            const chainIdProvider = (await ethers.provider.getNetwork()).chainId;
            const chainId = Number(chainIdProvider);
            const rollupDB = await RollupDB(new SMTMemDB(), chainId);
            const maxL1Tx = 256;
            const maxTx = 512;
            const nLevels = 32;

            const batchNum = await sybil.nextL1FillingQueue()
            const l1UserTxsLen = await sybil.lastIdx()

            // forge empty batch
            const forgerTest = new ForgerTest(
                maxTx,
                maxL1Tx,
                nLevels,
                sybil,
                rollupDB
            )
            await forgerTest.forgeBatch(true, [], []);

            // add deposit L1 transaction
            const babyjubjub = `0x${accounts[0].bjjCompressed}`;
            const loadAmount = float40.round(10);

            // forge deposit L1 transaction
            const l1TxUserArray = [];
            l1TxUserArray.push(
              await l1UserTxCreateAccountDeposit(loadAmount, babyjubjub, owner, sybil)
            )

            await forgerTest.forgeBatch(true, l1TxUserArray, []);

            // add exit L1 transaction


            console.log(res)
      
            // await expect(sybil.addL1Transaction(
            //   babyjubjub,
            //   fromIdx,
            //   loadAmount,
            //   amountF0,
            //   toIdx, 
            //   {value: 10}
            // )).to.emit(sybil, "L1UserTxEvent")    
            
            // // forge user "deposit" transaction
            // await sybil.forgeBatch(
            //     newLastIdx = await sybil.lastIdx() + 1n,
            //     newStRoot = 257,
            //     newExitRoot = await sybil.lastForgedBatch() + 1n,
            //     encodedL1CoordinatorTx = "0x00",
            //     l1L2TxsData = "0x00",
            //     feeIdxCoordinator = "0x00",
            //     verifierIdx = 0,
            //     l1Batch = true,
            //     proofA = ["0", "0"],
            //     proofB = [
            //       ["0", "0"],
            //       ["0", "0"],
            //     ],
            //     proofC = ["0", "0"],
            // )

            // // instant withdraw with merkle proof

            // const instantWithdraw = false;
            // const numExitRoot = await sybil.lastForgedBatch();

            // const state = await rollupDB.getStateByIdx(1);
            // const exitInfo = await rollupDB.getExitTreeInfo(255, 0);

            // console.log(exitInfo)
            // console.log(state)
            // console.log(rollupDB)

            // await sybil.withdrawMerkleProof(
            //     10n,
            //     `0x0`,
            //     numExitRoot,
            //     [],
            //     fromIdx,
            //     instantWithdraw
            // )
        })
      })
})