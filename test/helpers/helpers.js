const Scalar = require("ffjavascript").Scalar;
const poseidonUnit = require("circomlib/src/poseidon_gencontract");
const { expect } = require("chai");

const {
  float40, txUtils
} = require("@hermeznetwork/commonjs");

const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");

const L1_USER_BYTES = 74;

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

async function deployAndInitializeSybilFixture() {
  const [owner] = await ethers.getSigners();

  const Sybil = await ethers.getContractFactory("Sybil");
  const sybil = await Sybil.deploy();
  contractAddress = await sybil.getAddress();

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

  return { sybil, owner, contractAddress };
}

function calculateInputMaxTxLevels(maxTxArray, nLevelsArray) {
  let returnArray = [];
  for (let i = 0; i < maxTxArray.length; i++) {
    returnArray.push(
      Scalar.add(Scalar.e(maxTxArray[i]), Scalar.shl(nLevelsArray[i], 256 - 8))
    );
  }
  return returnArray;
}

class ForgerTest {
  constructor(maxTx, maxL1Tx, nLevels, sybil, rollupDB, verifier) {
    this.rollupDB = rollupDB;
    this.maxTx = maxTx;
    this.maxL1Tx = maxL1Tx;
    this.nLevels = nLevels;
    this.sybil = sybil;
    this.verifier = verifier;

    this.L1TxB = 544;
  }

  async forgeBatch(l1Batch, l1TxUserArray, l1TxCoordiatorArray, l2txArray) {
    const bb = await this.rollupDB.buildBatch(
      this.maxTx,
      this.nLevels,
      this.maxL1Tx
    );

    let jsL1TxData = "";
    for (let tx of l1TxUserArray) {
      bb.addTx(txUtils.decodeL1TxFull(tx));
      jsL1TxData = jsL1TxData + tx.slice(2);
    }

    // check L1 user tx are the same in batchbuilder and contract
    const currentQueue = await this.sybil.nextL1ToForgeQueue();
    const SCL1TxData = await this.sybil.mapL1TxQueue(currentQueue);
    console.log(SCL1TxData)
    // expect(SCL1TxData).to.equal(`0x${jsL1TxData}`);


    if (l1TxCoordiatorArray) {
      for (let tx of l1TxCoordiatorArray) {
        bb.addTx(txUtils.decodeL1TxFull(tx.l1TxBytes));
      }
    }


    if (l2txArray) {
      for (let tx of l2txArray) {
        bb.addTx(tx);
      }
    }

    // if(log) {
    //   bb.addToken(1);
    //   bb.addFeeIdx(259);
    // }

    await bb.build();

    let stringL1CoordinatorTx = "";
    for (let tx of l1TxCoordiatorArray) {
      stringL1CoordinatorTx =
        stringL1CoordinatorTx + tx.l1TxCoordinatorbytes.slice(2); // retireve the 0x
    }


    let proofA, proofB, proofC;

    // mock verifier
    proofA = ["0", "0"];
    proofB = [
      ["0", "0"],
      ["0", "0"],
    ];
    proofC = ["0", "0"];
  
    const newLastIdx = bb.getNewLastIdx();
    const newStateRoot = bb.getNewStateRoot();
    const newExitRoot = bb.getNewExitRoot();
    const compressedL1CoordinatorTx = `0x${stringL1CoordinatorTx}`;
    const L1L2TxsData = bb.getL1L2TxsDataSM();
    const feeIdxCoordinator = bb.getFeeTxsDataSM();
    const verifierIdx = 0;

    let implementCalculateInputTest = false;
    for (const functionSC in this.sybil.interface.functions) {
      if (this.sybil.interface.functions[functionSC].name == "calculateInputTest") {
        implementCalculateInputTest = true;
        break;
      }
    }

    if (implementCalculateInputTest)
      await expect(
        this.sybil.calculateInputTest(
          newLastIdx,
          newStateRoot,
          newExitRoot,
          compressedL1CoordinatorTx,
          L1L2TxsData,
          feeIdxCoordinator,
          l1Batch,
          verifierIdx
        )
      )
        .to.emit(this.sybil, "ReturnUint256")
        .withArgs(bb.getHashInputs());

    await expect(
      this.sybil.forgeBatch(
        newLastIdx,
        newStateRoot,
        newExitRoot,
        compressedL1CoordinatorTx,
        L1L2TxsData,
        feeIdxCoordinator,
        verifierIdx,
        l1Batch,
        proofA,
        proofB,
        proofC
      )
    ).to.emit(this.sybil, "ForgeBatch")
      .withArgs(bb.batchNumber, l1TxUserArray.length);

    await this.rollupDB.consolidate(bb);
  }
}

async function l1UserTxCreateAccountDeposit(
  loadAmount,
  babyjub,
  wallet,
  sybil,
) {
  const loadAmountF = float40.fix2Float(loadAmount);
  const fromIdx0 = 0;
  const amountF0 = 0;
  const toIdx0 = 0;

  // equivalent L1 transaction:
  const l1Txbytes = ethers.solidityPacked(["address", "uint256", "uint48", "uint40", "uint40", "uint48"], 
    [await wallet.getAddress(), babyjub, fromIdx0, loadAmountF, amountF0, toIdx0]
  )

  const lastQueue = await sybil.nextL1FillingQueue();

  const lastQueueBytes = await sybil.mapL1TxQueue(lastQueue);

  const currentIndex = (lastQueueBytes.length - 2) / 2 / L1_USER_BYTES; // -2 --> 0x, /2 --> 2 hex digits = 1 byte

  // ether
  let txRes;
  await expect(
    txRes = await sybil.connect(wallet).addL1Transaction(
        babyjub,
        fromIdx0,
        loadAmountF,
        amountF0,
        toIdx0,
      {
        value: loadAmount
      }
    )
  )
    .to.emit(sybil, "L1UserTxEvent")
    .withArgs(lastQueue, currentIndex, l1Txbytes);
  await txRes.wait();

  return l1Txbytes;
}

async function l1UserTxForceExit(
  tokenID,
  fromIdx,
  amountF,
  wallet,
  sybil
) {
  const exitIdx = 1;
  // equivalent L1 transaction:
  const l1TxForceExit = {
    toIdx: exitIdx,
    tokenID: tokenID,
    amountF: amountF,
    loadAmountF: 0,
    fromIdx: fromIdx,
    fromBjjCompressed: 0,
    fromEthAddr: await wallet.getAddress(),
  };
  const l1Txbytes = `0x${txUtils.encodeL1TxFull(l1TxForceExit)}`;
  const a = ethers.solidityPacked(["address", "uint256", "uint48", "uint40", "uint40", "uint48"], 
    [await wallet.getAddress(), babyjub, fromIdx0, loadAmountF, amountF0, toIdx0]
  )

  const lastQueue = await sybil.nextL1FillingQueue();

  const lastQueueBytes = await sybil.mapL1TxQueue(lastQueue);

  const currentIndex = (lastQueueBytes.length - 2) / 2 / L1_USER_BYTES; // -2 --> 0x, /2 --> 2 hex digits = 1 byte

  await expect(
    sybil.connect(wallet).addL1Transaction(
      babyjub0,
      fromIdx,
      loadAmountF0,
      amountF,
      tokenID,
      exitIdx,
      emptyPermit,
    )
  )
    .to.emit(sybil, "L1UserTxEvent")
    .withArgs(lastQueue, currentIndex, l1Txbytes);

  return l1Txbytes;
}

module.exports = { 
  ForgerTest, 
  deploySybilFixture, 
  deployAndInitializeSybilFixture, 
  calculateInputMaxTxLevels, 
  l1UserTxCreateAccountDeposit, 
  l1UserTxForceExit 
};
  