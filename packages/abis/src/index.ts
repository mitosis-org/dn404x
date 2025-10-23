import xDN404BaseAbi from './xDN404Base.js';
import xMorseAbi from './xMorse.js';
import xMorseCollateralAbi from './xMorseCollateral.js';
import xMorseStakingAbi from './xMorseStaking.js';
import interfacesExports from './interfaces/index.js';
import libsExports from './libs/index.js';
import peripheryExports from './periphery/index.js';

const abis = {
  xDN404Base: xDN404BaseAbi,
  xMorse: xMorseAbi,
  xMorseCollateral: xMorseCollateralAbi,
  xMorseStaking: xMorseStakingAbi,
  interfaces: interfacesExports,
  libs: libsExports,
  periphery: peripheryExports,
};

export default abis;
