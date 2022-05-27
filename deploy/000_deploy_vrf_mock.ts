/* eslint-disable node/no-unpublished-import */
/* eslint-disable node/no-missing-import */
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const deployVRFMock: DeployFunction = async function (
    hre: HardhatRuntimeEnvironment
) {
    const { getNamedAccounts } = hre;
    const { deploy, log } = hre.deployments;
    const { deployer } = await getNamedAccounts();
    const BASE_FEE = hre.ethers.utils.parseEther("0.1");
    const GAS_PRICE_LINK = 10 ** 9;
    const args = [BASE_FEE, GAS_PRICE_LINK];
    const vrfCoordinatorV2Mock = await deploy("VRFCoordinatorV2Mock", {
        from: deployer,
        log: true,
        args,
    });
    log(
        "You have deployed the vrfCoordinatorV2Mock contract to:",
        vrfCoordinatorV2Mock.address
    );
};
export default deployVRFMock;
deployVRFMock.tags = ["mocks"];
