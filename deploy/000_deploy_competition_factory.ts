/* eslint-disable node/no-unpublished-import */
/* eslint-disable node/no-missing-import */
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const deployCompetitionFactory: DeployFunction = async function (
    hre: HardhatRuntimeEnvironment
) {
    const { getNamedAccounts } = hre;
    const { deploy, log } = hre.deployments;
    const { deployer } = await getNamedAccounts();
    const CompetitionFactory = await deploy("CompetitionFactory", {
        from: deployer,
        log: true,
        args: [
            process.env.CHAINLINK_TOKEN!,
            process.env.CHAINLINK_ORACLE!,
            process.env.CHAINLINK_VRFCOORDINATOR!,
            process.env.CHAINLINK_JOBID!,
            process.env.CHAINLINK_KEYHASH!,
        ],
    });
    log(
        "You have deployed the CompetitionFactory contract to:",
        CompetitionFactory.address
    );
};
export default deployCompetitionFactory;
deployCompetitionFactory.tags = ["all", "factory"];
