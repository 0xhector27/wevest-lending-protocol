import chai from 'chai';
import { ethers } from "hardhat";
import { solidity } from "ethereum-waffle";

import { TestEnv, makeSuite } from './helpers/make-suite';
import { 
    unlockAccount, 
    convertToCurrencyDecimals 
} from './helpers/utils';

import { APPROVAL_AMOUNT_LENDING_POOL } from './helpers/constants';

chai.use(solidity);
const { expect } = chai;

makeSuite('Lending Pool', (testEnv: TestEnv) => {
    let whaleSigner: any;
    let aaveBalance: any;

    before(async () => {
        const { userA, usdc, lendingPool, yieldFarmingPool, usdcYVault } = testEnv;
        const whaleAddress = "0xb55167e8c781816508988A75cB15B66173C69509";

        unlockAccount(whaleAddress);
        whaleSigner = await ethers.provider.getSigner(whaleAddress);

        await userA.sendTransaction({
            to: whaleAddress,
            value: ethers.utils.parseEther("100"),
        });
        
        // before start, first create 1000 USDC in userA account
        const initialAmount = await convertToCurrencyDecimals(usdc.address, "1000");

        await usdc
            .connect(whaleSigner)
            .transfer(await userA.getAddress(), initialAmount);

        await usdc
            .connect(userA)
            .approve(lendingPool.address, APPROVAL_AMOUNT_LENDING_POOL);
        
        // initialize YieldFarmingPool
        await usdc
            .connect(whaleSigner)
            .transfer(yieldFarmingPool.address, initialAmount);
        
        await yieldFarmingPool
            .connect(userA)
            .deposit(usdcYVault.address, usdc.address, await convertToCurrencyDecimals(usdc.address, "100"));
    });

    describe("Deposit", async () => {
        it("UserA deposits 100 USDC", async () => {
            const { lendingPool, usdc, userA, wvUsdc } = testEnv;
            // amount to deposit
            const amountToDeposit = await convertToCurrencyDecimals(usdc.address, "100");
            
            await lendingPool
                .connect(userA)
                .deposit(usdc.address, amountToDeposit);
            // get current pool balance
            const poolBalance = await wvUsdc.totalSupply();
            console.log("USDC Pool Balance", poolBalance.toString());
            // compare balance number
            expect(poolBalance.toString()).to.be.equal(
                amountToDeposit.toString(), 
                "Invalid pool balance"
            );
            // get current userA LP token balance
            const wvUsdcBalance = await wvUsdc.balanceOf(await userA.getAddress());
            console.log("UserA wvUSDC balance: ", wvUsdcBalance.toString());

            expect(wvUsdcBalance.toString()).to.be.equal(
                amountToDeposit.toString(),
                "Invalid userA LP token balance"
            );
        });
    });
    
    describe("Withdraw", async () => {
        it("UserA withdraws 100 wvUSDC", async() => {
            const { lendingPool, userA, wvUsdc, usdc } = testEnv;

            const requestWithdraw = await convertToCurrencyDecimals(usdc.address, "100");
            const prevPoolBalance = await wvUsdc.totalSupply();
            console.log("USDC Pool prev balance", prevPoolBalance.toString());

            const prevUsdcBalance = await usdc.balanceOf(await userA.getAddress());
            console.log("UserA USDC prev balance: ", prevUsdcBalance.toString());

            await lendingPool
                .connect(userA)
                .withdraw(usdc.address, requestWithdraw);

            const updatedPoolBalance = await wvUsdc.totalSupply();
            console.log("USDC Pool updated balance", updatedPoolBalance.toString());

            const updatedUsdcBalance = await usdc.balanceOf(await userA.getAddress());
            console.log("UserA USDC updated balance: ", updatedUsdcBalance.toString());

            const wvUsdcBalance = await wvUsdc.balanceOf(await userA.getAddress());
            console.log("UserA wvUSDC updated balance: ", wvUsdcBalance.toString());
        });
    });

    describe("Borrow", async () => {
        it("UserA deposit 100 USDC as collateral, and want to borrow AAVE with 3x leverage", async() => {
            const { lendingPool, userA, usdc, aave } = testEnv;
            // First deposit enough pool balance to test borrow function
            await usdc
                .connect(whaleSigner)
                .approve(lendingPool.address, APPROVAL_AMOUNT_LENDING_POOL);

            await lendingPool
                .connect(whaleSigner)
                .deposit(usdc.address, await convertToCurrencyDecimals(usdc.address, "1000"));
            
            // call borrow function
            await lendingPool
                .connect(userA)
                .borrow(usdc.address, await convertToCurrencyDecimals(usdc.address, "100"), aave.address, 3);

            const { protocolDataProvider } = testEnv;

            // get userA wvUSDC, debtUSDC balance
            const [ 
                currentWvUsdcBal, 
                currentDebt,
                principalDebt,
                usageAsCollateralEnabled
            ] = await protocolDataProvider.getUserReserveData(
                usdc.address, 
                await userA.getAddress()
            );
            console.log("UserA wvUSDC balance: ", currentWvUsdcBal.toString());
            console.log("UserA debtUSDC balance: ", currentDebt.toString());
        });
    });

    describe("YF Pool transfer request", async () => {
        it("Send total balance of selected asset to Yearn Finance", async () => {
            const { yieldFarmingPool, aave, userA, aaveYVault } =  testEnv;
            // check balance of selected asset
            aaveBalance = await aave.balanceOf(yieldFarmingPool.address);
            console.log("AAVE balance", aaveBalance.toString());

            // Send selected asset to Yearn Finance protocol
            await yieldFarmingPool
                .connect(userA)
                .deposit(aaveYVault.address, aave.address, aaveBalance);

            // Check current balance of underlying asset and yVault token after transfer
            const afterBalance = await aave.balanceOf(yieldFarmingPool.address);
            console.log("AAVE balance after transfer", afterBalance.toString());

            const vaultTokenBalance = await yieldFarmingPool.currentBalance(aaveYVault.address);
            console.log("vault balance after transfer", vaultTokenBalance.toString());

            /* expect(vaultTokenBalance.toString()).to.be.equal(
                aaveBalance.toString(),
                "Invalid yVault balance"
            ); */
        });
    });

    describe("Redeem", async () => {
        it("UserA redeem 100 debtUSDC loan", async() => {
            const { lendingPool, userA, usdc, aave } = testEnv;
            await lendingPool
                .connect(userA)
                .redeem(
                    aave.address, 
                    usdc.address, 
                    await convertToCurrencyDecimals(usdc.address, "100")
                );
        });
    });
});
