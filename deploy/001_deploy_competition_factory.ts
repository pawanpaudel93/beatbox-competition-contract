/* eslint-disable node/no-unpublished-import */
/* eslint-disable node/no-missing-import */
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const deployCompetitionFactory: DeployFunction = async function (
    hre: HardhatRuntimeEnvironment
) {
    const { getNamedAccounts, network, run } = hre;
    const { deploy, log } = hre.deployments;
    const { deployer } = await getNamedAccounts();
    let args = [];
    if (network.name !== "hardhat" && network.name !== "localhost") {
        args = [
            process.env.CHAINLINK_TOKEN!,
            process.env.CHAINLINK_ORACLE!,
            process.env.CHAINLINK_VRFCOORDINATOR!,
            process.env.CHAINLINK_JOBID!,
            process.env.CHAINLINK_KEYHASH!,
        ];
    } else {
        const vrfCoordinatorV2Mock = await hre.ethers.getContract(
            "VRFCoordinatorV2Mock"
        );
        args = [
            process.env.CHAINLINK_TOKEN!,
            process.env.CHAINLINK_ORACLE!,
            vrfCoordinatorV2Mock.address,
            process.env.CHAINLINK_JOBID!,
            process.env.CHAINLINK_KEYHASH!,
        ];
    }
    const CompetitionFactory = await deploy("CompetitionFactory", {
        from: deployer,
        log: true,
        args,
    });
    log(
        "You have deployed the CompetitionFactory contract to:",
        CompetitionFactory.address
    );
    if (network.name !== "hardhat" && network.name !== "localhost") {
        // sleep for 20s
        await new Promise((resolve) => setTimeout(resolve, 60000));
        await run("verify:verify", {
            address: CompetitionFactory.address,
            constructorArguments: args,
        });
    }
};
export default deployCompetitionFactory;
deployCompetitionFactory.tags = ["all", "factory"];
