const Scalar = require("ffjavascript").Scalar;

function calculateInputMaxTxLevels(maxTxArray, nLevelsArray) {
    let returnArray = [];
    for (let i = 0; i < maxTxArray.length; i++) {
      returnArray.push(
        Scalar.add(Scalar.e(maxTxArray[i]), Scalar.shl(nLevelsArray[i], 256 - 8))
      );
    }
    return returnArray;
}

module.exports = { calculateInputMaxTxLevels };
  