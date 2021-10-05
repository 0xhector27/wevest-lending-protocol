export enum eEthereumNetwork {
    main = 'main',
    kovan = 'kovan',
    ropsten = 'ropsten',
    hardhat = 'hardhat'
}

export enum ePolygonNetwork {
    matic = 'matic',
    mumbai = 'mumbai',
}

export enum ContractId {
    LendingPoolAddressesProvider = 'LendingPoolAddressesProvider',
    LendingPoolAddressesProviderRegistry = 'LendingPoolAddressesProviderRegistry',
    LendingPoolConfigurator = 'LendingPoolConfigurator',
    ValidationLogic = 'ValidationLogic',
    ReserveLogic = 'ReserveLogic',
    GenericLogic = 'GenericLogic',
    LendingPool = 'LendingPool',
    PriceOracle = 'PriceOracle',
    MockAggregator = 'MockAggregator',
    WevestOracle = 'WevestOracle',
    LendingPoolCollateralManager = 'LendingPoolCollateralManager',
    WvToken = 'WvToken',
    WevestProtocolDataProvider = 'WevestProtocolDataProvider',
    DebtToken = 'DebtToken',
    LendingPoolImpl = 'LendingPoolImpl',
    LendingPoolConfiguratorImpl = 'LendingPoolConfiguratorImpl',
    LendingPoolCollateralManagerImpl = 'LendingPoolCollateralManagerImpl',
    IERC20Detailed = 'IERC20Detailed'
}

export enum TokenContractId {
    DAI = 'DAI',
    AAVE = 'AAVE',
    TUSD = 'TUSD',
    BAT = 'BAT',
    WETH = 'WETH',
    USDC = 'USDC',
    USDT = 'USDT',
    SUSD = 'SUSD',
    ZRX = 'ZRX',
    MKR = 'MKR',
    WBTC = 'WBTC',
    LINK = 'LINK',
    KNC = 'KNC',
    MANA = 'MANA',
    REN = 'REN',
    SNX = 'SNX',
    BUSD = 'BUSD',
    USD = 'USD',
    YFI = 'YFI',
    UNI = 'UNI',
    ENJ = 'ENJ'
}

export enum LeverageRatioMode {
    HALF = 0, // 0.5x
    ONE = 1, // 1x
    TWO = 2, // 2x
    THREE = 3 // 3x
}

export interface SymbolMap<T> {
    [symbol: string]: T;
}

export type iParamsPerNetwork<T> = 
 | iEthereumParamsPerNetwork<T> 
 | iPolygonParamsPerNetwork<T>

export interface iEthereumParamsPerNetwork<T> {
    [eEthereumNetwork.main]: T;
    [eEthereumNetwork.kovan]: T;
    [eEthereumNetwork.ropsten]: T;
    [eEthereumNetwork.hardhat]: T;
}

export interface iPolygonParamsPerNetwork<T> {
    [ePolygonNetwork.matic]: T;
    [ePolygonNetwork.mumbai]: T;
}

export interface IMarketConfiguration {
    MarketId: string;
    ProviderId: number;
    ReserveAssets: iParamsPerNetwork<SymbolMap<string>>;
}

export enum ConfigNames {
    Ethereum = 'Ethereum',
    Polygon = 'Polygon',
}