export interface SymbolMap<T> {
  [symbol: string]: T;
}

export enum eNetwork {
  mainnet = 'mainnet',
  testnet = 'testnet',
  hardhat = 'hardhat',
  harhatevm = 'harhatevm',
}

export type tEthereumAddress = string;
export type tStringTokenBigUnits = string;
export type tStringTokenSmallUnits = string;

export type iParamsPerNetworkAll<T> = iParamsPerNetwork<T>

export interface iParamsPerNetwork<eNetwork> {
  [eNetwork.mainnet]: eNetwork;
  [eNetwork.testnet]: eNetwork;
  [eNetwork.hardhat]: eNetwork;
  [eNetwork.harhatevm]: eNetwork;
}

export interface ObjectString {
  [key: string]: string;
}
