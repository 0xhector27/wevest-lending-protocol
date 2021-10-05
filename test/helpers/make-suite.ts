import { ethers } from "hardhat";
import { Signer, BigNumberish } from "ethers";
import hre from "hardhat";
import {
    LendingPool__factory,
    LendingPoolConfigurator__factory,
    WvToken__factory,
    MintableERC20__factory,
    YieldFarmingPool__factory,
    PriceOracle__factory,
    TokenSwap__factory
} from '../../types';
import { 
    MOCK_CHAINLINK_AGGREGATORS_PRICES, 
    PROTOCOL_GLOBAL_PARAMS,
    oneEther 
} from "./constants";

export interface TestEnv {
    deployer: Signer;
    signers: Signer[];
    userA: Signer;
    wvUsdc: any;
    wvAave: any;
    usdc: any;
    aave: any;
    lendingPool: any;
    lendingPoolAddressesProvider: any;
    lendingPoolConfigurator: any;
    protocolDataProvider: any;
    yieldFarmingPool: any;
    tokenSwap: any;
    usdcYVault: any;
    aaveYVault: any;
    interestRateStrategy: any;
}

const testEnv: TestEnv = {
    deployer: {} as Signer,
    signers: [] as Signer[],
    userA: {} as Signer,
    wvUsdc: {} as any,
    wvAave: {} as any,
    usdc: {} as any,
    aave: {} as any,
    lendingPool: {} as any,
    lendingPoolAddressesProvider: {} as any,
    lendingPoolConfigurator: {} as any,
    protocolDataProvider: {} as any,
    yieldFarmingPool: {} as any,
    tokenSwap: {} as any,
    usdcYVault: {} as any,
    aaveYVault: {} as any,
    interestRateStrategy: {} as any
}

export const unlockAccount = async (address: string) => {
    await hre.network.provider.send("hardhat_impersonateAccount", [address]);
    return address;
};

export async function initialize() {
    const signers = await ethers.getSigners();
    testEnv.signers = signers;
    testEnv.deployer = signers[0];
    testEnv.userA = signers[1];

    const LendingPoolAddressesProvider = await ethers.getContractFactory("LendingPoolAddressesProvider");
    testEnv.lendingPoolAddressesProvider = await LendingPoolAddressesProvider.deploy("Main Market");
    await testEnv.lendingPoolAddressesProvider.deployed();
    console.log("LendingPoolAddressesProvider deployed to:", testEnv.lendingPoolAddressesProvider.address);

    await testEnv.lendingPoolAddressesProvider.setPoolAdmin(await testEnv.deployer.getAddress());
    await testEnv.lendingPoolAddressesProvider.setEmergencyAdmin(await signers[1].getAddress());

    // deploy logic libraries used by Lending Pool
    const reserveLogicLibFactory = await ethers.getContractFactory("ReserveLogic");
    const reserveLogicLibContract = await reserveLogicLibFactory.deploy();
    await reserveLogicLibContract.deployed();

    const genericLogicLibFactory = await ethers.getContractFactory("GenericLogic");
    const genericLogicLibContract = await genericLogicLibFactory.deploy();
    await genericLogicLibContract.deployed();

    const validationLogicLibFactory = await ethers.getContractFactory("ValidationLogic", {
        libraries: {
            GenericLogic: genericLogicLibContract.address
        }
    });
    const validationLogicLibContract = await validationLogicLibFactory.deploy();
    await validationLogicLibContract.deployed();

    // LendingPool contract
    const LendingPool = await ethers.getContractFactory("LendingPool", {
        libraries: {
            ReserveLogic: reserveLogicLibContract.address,
            ValidationLogic: validationLogicLibContract.address
        },
    });
    const lendingPool = await LendingPool.deploy();
    await lendingPool.deployed();

    // update implementation as proxy contract
    await testEnv.lendingPoolAddressesProvider.setLendingPoolImpl(lendingPool.address);
    const lendingPoolAddress = await testEnv.lendingPoolAddressesProvider.getLendingPool();

    // get LendingPoolProxy contract
    testEnv.lendingPool = await LendingPool__factory.connect(lendingPoolAddress, testEnv.deployer);
    console.log("LendingPool deployed to:", testEnv.lendingPool.address);

    const LendingPoolConfigurator = await ethers.getContractFactory("LendingPoolConfigurator");
    const lendingPoolConfigurator  = await LendingPoolConfigurator.deploy();
    await lendingPoolConfigurator.deployed();

    // update as proxy contract
    await testEnv.lendingPoolAddressesProvider.setLendingPoolConfiguratorImpl(lendingPoolConfigurator.address);
    const lendingPoolConfiguratorAddress = await testEnv.lendingPoolAddressesProvider.getLendingPoolConfigurator();
    // get LendingPoolConfiguratorProxy contract
    testEnv.lendingPoolConfigurator = await LendingPoolConfigurator__factory.connect(
        lendingPoolConfiguratorAddress, 
        testEnv.deployer
    );
    console.log("LendingPoolConfigurator deployed to:", testEnv.lendingPoolConfigurator.address);
    
    const tokenSwapFactory = await ethers.getContractFactory(
        "TokenSwap",
        testEnv.deployer
    );

    const tokenSwap = await tokenSwapFactory.deploy();
    await tokenSwap.deployed();

    // update implementation as proxy contract
    await testEnv.lendingPoolAddressesProvider.setTokenSwapImpl(tokenSwap.address);
    const tokenSwapAddress = await testEnv.lendingPoolAddressesProvider.getTokenSwap();

    // get LendingPoolProxy contract
    testEnv.tokenSwap = await TokenSwap__factory.connect(tokenSwapAddress, testEnv.deployer);
    console.log("TokenSwap deployed to:", testEnv.tokenSwap.address);

    const USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
    testEnv.usdc = await ethers.getContractAt(
        "IUSDC",
        USDC
    );
    console.log("USDC deployed to:", testEnv.usdc.address);
    
    const AAVE = "0x7fc66500c84a76ad7e9c93437bfc5ac33e2ddae9";
    testEnv.aave = await ethers.getContractAt(
        "IAAVE",
        AAVE
    );
    console.log("AAVE deployed to:", testEnv.aave.address);

    const treasuryExample = "0x488177c42bD58104618cA771A674Ba7e4D5A2FBB";

    const WvUSDCFactory = await ethers.getContractFactory("WvToken");
    const wvUSDCContract = await WvUSDCFactory.deploy();
    await wvUSDCContract.deployed();

    await wvUSDCContract.initialize(
        testEnv.lendingPool.address,
        treasuryExample,
        testEnv.usdc.address,
        6,
        'Wevest interest bearing USDC',
        'wvUSDC'
    );
    
    const WvAAVEFactory = await ethers.getContractFactory("WvToken");
    const wvAAVEContract = await WvAAVEFactory.deploy();
    await wvAAVEContract.deployed();

    await wvAAVEContract.initialize(
        testEnv.lendingPool.address,
        treasuryExample,
        testEnv.aave.address,
        18,
        'Wevest interest bearing AAVE',
        'wvAAVE'
    );

    const DebtUSDCFactory = await ethers.getContractFactory("DebtToken");
    const debtUSDCContract = await DebtUSDCFactory.deploy();
    await debtUSDCContract.deployed();

    await debtUSDCContract.initialize(
        testEnv.lendingPool.address,
        testEnv.usdc.address,
        6,
        'Wevest debt bearing USDC',
        'debtUSDC'
    );

    const DebtAAVEFactory = await ethers.getContractFactory("DebtToken");
    const debtAAVEContract = await DebtAAVEFactory.deploy();
    await debtAAVEContract.deployed();

    await debtAAVEContract.initialize(
        testEnv.lendingPool.address,
        testEnv.usdc.address,
        18,
        'Wevest debt bearing AAVE',
        'debtAAVE'
    );
    
    const InterestRateStrategy = await ethers.getContractFactory("DefaultReserveInterestRateStrategy");
    testEnv.interestRateStrategy = await InterestRateStrategy.deploy(testEnv.lendingPoolAddressesProvider.address);
    await testEnv.interestRateStrategy.deployed();
    
    console.log("DefaultReserveInterestRateStrategy deployed to:", testEnv.interestRateStrategy.address);
    
    const USDC_YVAULT = "0xa354F35829Ae975e850e23e9615b11Da1B3dC4DE";

    testEnv.usdcYVault = await ethers.getContractAt(
        "IVault",
        USDC_YVAULT
    );
    
    const AAVE_YVAULT = "0xd9788f3931Ede4D5018184E198699dC6d66C1915";
    testEnv.aaveYVault = await ethers.getContractAt(
        "IVault",
        AAVE_YVAULT
    );

    let initReserveParams: {
        wvTokenImpl: string;
        debtTokenImpl: string;
        vaultTokenAddress: string;
        underlyingAsset: string;
        underlyingAssetName: string;
        underlyingAssetDecimals: BigNumberish;
        interestRateStrategyAddress: string;
        treasury: string;
        wvTokenName: string;
        wvTokenSymbol: string;
        debtTokenName: string;
        debtTokenSymbol: string;
    }[] = [];

    initReserveParams.push({
        wvTokenImpl: wvUSDCContract.address,
        debtTokenImpl: debtUSDCContract.address,
        vaultTokenAddress: testEnv.usdcYVault.address,
        underlyingAsset: testEnv.usdc.address,
        underlyingAssetName: await testEnv.usdc.name(),
        underlyingAssetDecimals: await testEnv.usdc.decimals(),
        interestRateStrategyAddress: testEnv.interestRateStrategy.address,
        treasury: treasuryExample,
        wvTokenName: await wvUSDCContract.name(),
        wvTokenSymbol: await wvUSDCContract.symbol(),
        debtTokenName: await debtUSDCContract.name(),
        debtTokenSymbol: await debtUSDCContract.symbol()
    }, {
        wvTokenImpl: wvAAVEContract.address,
        debtTokenImpl: debtAAVEContract.address,
        vaultTokenAddress: testEnv.aaveYVault.address,
        underlyingAsset: testEnv.aave.address,
        underlyingAssetName: await testEnv.aave.name(),
        underlyingAssetDecimals: await testEnv.aave.decimals(),
        interestRateStrategyAddress: testEnv.interestRateStrategy.address,
        treasury: treasuryExample,
        wvTokenName: await wvAAVEContract.name(),
        wvTokenSymbol: await wvAAVEContract.symbol(),
        debtTokenName: await debtAAVEContract.name(),
        debtTokenSymbol: await debtAAVEContract.symbol()
    });

    await testEnv.lendingPoolConfigurator.batchInitReserve(initReserveParams);

    // deploy ProtocolDataProvider
    const ProtocolDataProvider = await ethers.getContractFactory("WevestProtocolDataProvider");
    testEnv.protocolDataProvider  = await ProtocolDataProvider.deploy(testEnv.lendingPoolAddressesProvider.address);
    await testEnv.protocolDataProvider.deployed();
    console.log("ProcotolDataProvider deployed to:", testEnv.protocolDataProvider.address);
    
    const allWvTokens = await testEnv.protocolDataProvider.getAllWvTokens();
    const wvUSDCAddress = allWvTokens.find(
        (wvToken: { symbol: string; }) => wvToken.symbol === 'wvUSDC'
    )?.tokenAddress;
    testEnv.wvUsdc = await WvToken__factory.connect(wvUSDCAddress, testEnv.deployer);
    console.log("wvUSDC proxy deployed:", testEnv.wvUsdc.address);

    const wvAAVEAddress = allWvTokens.find(
        (wvToken: { symbol: string; }) => wvToken.symbol === 'wvAAVE'
    )?.tokenAddress;
    testEnv.wvAave = await WvToken__factory.connect(wvAAVEAddress, testEnv.deployer);
    console.log("wvAAVE proxy deployed:", testEnv.wvAave.address);

    // deploy YieldFarmingPool
    const YieldFarmingPool = await ethers.getContractFactory("YieldFarmingPool");
    const yieldFarmingPool  = await YieldFarmingPool.deploy();
    await yieldFarmingPool.deployed();

    // update as proxy contract
    await testEnv.lendingPoolAddressesProvider.setYieldFarmingPoolImpl(yieldFarmingPool.address);
    const yieldFarmingPoolAddress = await testEnv.lendingPoolAddressesProvider.getYieldFarmingPool();
    // get yfpool proxy contract
    testEnv.yieldFarmingPool = await YieldFarmingPool__factory.connect(yieldFarmingPoolAddress, testEnv.deployer);

    console.log("YieldFarmingPool deployed to:", testEnv.yieldFarmingPool.address);

    // setup price oracle
    const priceOracle =  await ethers.getContractFactory("PriceOracle");
    const fallbackOracle = await priceOracle.deploy();
    await fallbackOracle.deployed();

    await fallbackOracle.setEthUsdPrice(PROTOCOL_GLOBAL_PARAMS.MockUsdPriceInWei);
    // set initial asset price
    await fallbackOracle.setAssetPrice(testEnv.usdc.address, MOCK_CHAINLINK_AGGREGATORS_PRICES.USDC);
    await fallbackOracle.setAssetPrice(testEnv.aave.address, MOCK_CHAINLINK_AGGREGATORS_PRICES.AAVE);

    const MockAggregator = await ethers.getContractFactory("MockAggregator");
    const usdcMockAggregator = await MockAggregator.deploy(MOCK_CHAINLINK_AGGREGATORS_PRICES.USDC);
    await usdcMockAggregator.deployed();

    const aaveMockAggregator = await MockAggregator.deploy(MOCK_CHAINLINK_AGGREGATORS_PRICES.AAVE);
    await aaveMockAggregator.deployed();

    const WETHMocked = await ethers.getContractFactory("WETH9Mocked");
    const wethMocked = await WETHMocked.deploy();
    await wethMocked.deployed(); 

    const WevestOracle = await ethers.getContractFactory("WevestOracle");
    const wevestOracle = await WevestOracle.deploy(
        [
            testEnv.usdc.address,
            testEnv.aave.address
        ],
        [
            usdcMockAggregator.address,
            aaveMockAggregator.address
        ],
        fallbackOracle.address,
        wethMocked.address,
        oneEther.toString(),
    );
    await wevestOracle.deployed();

    await testEnv.lendingPoolAddressesProvider.setPriceOracle(fallbackOracle.address);
    // enabled borrowing
    await testEnv.lendingPoolConfigurator
        .connect(testEnv.deployer)
        .enableBorrowingOnReserve(testEnv.usdc.address);

    await testEnv.lendingPoolConfigurator
        .connect(testEnv.deployer)
        .enableBorrowingOnReserve(testEnv.aave.address);
}

export function makeSuite(name: string, tests: (testEnv: TestEnv) => void) {
    describe(name, () => {
      tests(testEnv);
    });
}
