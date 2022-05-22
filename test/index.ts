import { expect } from "chai";
import { Signer, Contract, Event } from "ethers";
import { ethers, deployments } from "hardhat";
import { generateRandomBeatboxers } from "./../utils";

describe("CompetitionFactory", () => {
    let competitionFactory: Contract;
    let competitionName: string,
        competitionDescription: string,
        imageURI: string;
    let deployer: Signer,
        competitionCreator: Signer,
        judgeOne: Signer,
        judgeTwo: Signer;

    let beatboxers: { addresses: string[]; names: string[] };

    beforeEach(async () => {
        await deployments.fixture(["all"]);
        [deployer, competitionCreator, judgeOne, judgeTwo] =
            await ethers.getSigners();
        competitionName = ethers.utils.formatBytes32String("BBU");
        competitionDescription = "Beatbox competition";
        imageURI = "ipfs://hash";
        beatboxers = await generateRandomBeatboxers();
        competitionFactory = await ethers.getContract(
            "CompetitionFactory",
            deployer
        );
    });

    it("Should deploy and create a beatbox competition contract", async () => {
        const beatboxTx = await competitionFactory.createCompetition(
            competitionName,
            competitionDescription,
            imageURI
        );
        const receipt = await beatboxTx.wait();
        await expect(beatboxTx)
            .to.emit(competitionFactory, "CompetitionCreated")
            .withArgs(
                0,
                await deployer.getAddress(),
                receipt.events![0].address,
                competitionName,
                competitionDescription,
                imageURI
            );
    });

    it("Should be able to create a battle", async () => {
        const beatboxTx = await competitionFactory
            .connect(competitionCreator)
            .createCompetition(
                competitionName,
                competitionDescription,
                imageURI
            );
        const receipt = await beatboxTx.wait();
        await expect(beatboxTx)
            .to.emit(competitionFactory, "CompetitionCreated")
            .withArgs(
                0,
                await competitionCreator.getAddress(),
                receipt.events![0].address,
                competitionName,
                competitionDescription,
                imageURI
            );
        const beatboxCompetitionAddress = receipt.events?.find(
            (event: Event) => event.event === "CompetitionCreated"
        )?.args?.contractAddress!;
        await expect(beatboxCompetitionAddress).to.not.be.undefined;
        const beatboxCompetition = await ethers.getContractAt(
            "BeatboxCompetition",
            beatboxCompetitionAddress,
            competitionCreator
        );
        let judgeTx = await beatboxCompetition.addJudge(
            await judgeOne.getAddress(),
            "Judge One"
        );
        await judgeTx.wait();
        judgeTx = await beatboxCompetition.addJudge(
            await judgeTwo.getAddress(),
            "Judge Two"
        );
        await judgeTx.wait();
        const wildcardStartTx = await beatboxCompetition.startWildcard();
        await wildcardStartTx.wait();
        const wildcardEndTx = await beatboxCompetition.endWildcard();
        await wildcardEndTx.wait();
        // await expect(
        //     beatboxCompetition
        //         .connect(competitionCreator)
        //         .addBeatboxers(beatboxers.addresses, beatboxers.names)
        // )
        //     .to.emit(beatboxCompetition, "BeatboxersAdded")
        //     .withArgs();
        // const setBattleOpponentsTx =
        //     await beatboxCompetition._setBattleOpponents(1234);
        // await setBattleOpponentsTx.wait();
        // const battleStartTime = Math.floor(new Date().getTime() / 1000);
        // const battleEndTime = battleStartTime + 24 * 60 * 60; // 1 day
        // const winningAmount = ethers.utils.parseEther("0.1");
        // const battleTx = await beatboxCompetition.startBattle(
        //     0,
        //     "Helium vs. Inertia",
        //     2,
        //     ethers.utils.formatBytes32String("dQw4w9WgXcQ").slice(0, 24),
        //     ethers.utils.formatBytes32String("dQw4w9WgXcQ").slice(0, 24),
        //     battleStartTime,
        //     battleEndTime,
        //     winningAmount
        // );
        // await battleTx.wait();
        // await expect(battleTx)
        //     .to.emit(beatboxCompetition, "BattleCreated")
        //     .withArgs(0, "Helium vs. Inertia", 2);
    });
});
