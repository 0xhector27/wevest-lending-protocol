import chai from 'chai';
import { TestEnv, makeSuite } from './helpers/make-suite';
import { unlockAccount } from './helpers/utils';
import { ethers } from "hardhat";
import { solidity } from "ethereum-waffle";

chai.use(solidity);
const { expect } = chai;

makeSuite('Token Swap', (testEnv: TestEnv) => {
    let erc20: any;
    const whaleAddress = "0xb55167e8c781816508988A75cB15B66173C69509";
    before(async () => {
        const { signers } =  testEnv;
        await signers[2].sendTransaction({
            to: whaleAddress,
            value: ethers.utils.parseEther("100"),
        });
        await unlockAccount(whaleAddress);

        erc20 = await ethers.getContractAt(
            "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
            ethers.constants.AddressZero
        );
    });

    it("swap USDC into AAVE", async () => {
        const { tokenSwap } =  testEnv;
        const USDC = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48";
        const AAVE = "0x7fc66500c84a76ad7e9c93437bfc5ac33e2ddae9";
        const AMOUNT_OUT_MIN = 1;
        const AMOUNT_IN = ethers.utils.parseUnits("100", 6);

        const TOKEN_IN = USDC;
        const TOKEN_OUT = AAVE;

        const tokenIn = await erc20.attach(TOKEN_IN);
        const tokenOut = await erc20.attach(TOKEN_OUT);

        const whaleSigner = await ethers.provider.getSigner(whaleAddress);

        await tokenIn
            .connect(whaleSigner)
            .approve(tokenSwap.address, ethers.utils.parseUnits("100", 6));

        await tokenSwap
            .connect(whaleSigner)
            .swap(tokenIn.address, tokenOut.address, AMOUNT_IN, AMOUNT_OUT_MIN, whaleAddress);

        const balance = await tokenOut.balanceOf(whaleAddress);
        console.log('swapped amount', balance.toString());
    });
});
