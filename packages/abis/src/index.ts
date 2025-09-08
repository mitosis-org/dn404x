import xDN404BaseAbi from './xDN404Base.js';
import xDN404TreasuryAbi from './xDN404Treasury.js';
import xMorseAbi from './xMorse.js';
import xMorseCollateralAbi from './xMorseCollateral.js';
import interfacesExports from './interfaces/index.js';
import libsExports from './libs/index.js';
import peripheryExports from './periphery/index.js';

const abis = {
  xDN404Base: xDN404BaseAbi,
  xDN404Treasury: xDN404TreasuryAbi,
  xMorse: xMorseAbi,
  xMorseCollateral: xMorseCollateralAbi,
  interfaces: interfacesExports,
  libs: libsExports,
  periphery: peripheryExports,
};

export default abis;
