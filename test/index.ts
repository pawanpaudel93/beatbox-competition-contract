import { expect } from "chai";
import { Signer } from "ethers";
import { ethers, deployments } from "hardhat";
import {
    CompetitionFactory as CompetitionFactoryContract,
    BbxCompetition as BbxCompetitionContract,
} from "./../typechain";

describe("CompetitionFactory", () => {
    let competitionFactory: CompetitionFactoryContract;
    let deployer: Signer,
        competitionCreator: Signer,
        beatboxerOne: Signer,
        beatboxerTwo: Signer,
        judgeOne: Signer,
        judgeTwo: Signer;

    beforeEach(async () => {
        await deployments.fixture(["all"]);
        [deployer, competitionCreator, beatboxerOne, beatboxerTwo] =
            await ethers.getSigners();
        competitionFactory = await ethers.getContract(
            "CompetitionFactory",
            deployer
        );
    });

    it("Should deploy and create a beatbox competition contract", async () => {
        const beatboxTx = await competitionFactory.createCompetition(
            "BBU",
            "BBU competition",
            "ipfs://hash"
        );
        const receipt = await beatboxTx.wait();
        expect(receipt)
            .to.emit(competitionFactory, "CompetitionCreated")
            .withArgs(
                0,
                "BBU",
                await deployer.getAddress(),
                receipt.events![0].address,
                "BBU Competition",
                "ipfs://hash"
            );
        expect((await competitionFactory.competitions(0)).name).to.equal("BBU");
        expect(
            (
                await competitionFactory.getCompetitionsByCreator(
                    await deployer.getAddress()
                )
            ).length
        ).greaterThan(0);
    });

    it("Should be able to create a battle", async () => {
        const beatboxTx = await competitionFactory
            .connect(competitionCreator)
            .createCompetition("BBU", "BBU competition", "ipfs://hash");
        const receipt = await beatboxTx.wait();
        const beatboxCompetitionAddress = receipt.events?.find(
            (event) => event.event === "CompetitionCreated"
        )?.address!;
        const beatboxCompetition: BbxCompetitionContract =
            await ethers.getContractAt(
                "BbxCompetition",
                beatboxCompetitionAddress
            );
        const beatboxerOneAddress = await beatboxerOne.getAddress();
        const beatboxerTwoAddress = await beatboxerTwo.getAddress();
        await beatboxCompetition
            .connect(competitionCreator)
            .addBeatboxer(beatboxerOneAddress, "Beatboxer One");
        await beatboxCompetition
            .connect(competitionCreator)
            .addBeatboxer(beatboxerTwoAddress, "Beatboxer Two");
        const battleStartTime = Math.floor(new Date().getTime() / 1000);
        const battleEndTime = battleStartTime + 24 * 60 * 60; // 1 day
        const winningAmount = ethers.utils.parseEther("0.1");
        const battleTx = await beatboxCompetition.startBattle(
            "Helium vs. Inertia",
            2,
            beatboxerOneAddress,
            beatboxerTwoAddress,
            "dQw4w9WgXcQ",
            "dQw4w9WgXcQ",
            battleStartTime,
            battleEndTime,
            winningAmount
        );
        const battleReceipt = await battleTx.wait();
        expect(battleReceipt)
            .to.emit(beatboxCompetition, "BattleCreated")
            .withArgs(
                0,
                beatboxerOneAddress,
                beatboxerTwoAddress,
                battleStartTime,
                battleEndTime,
                winningAmount
            );
    });
});
