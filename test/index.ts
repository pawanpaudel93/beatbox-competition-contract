import { expect } from "chai";
import { Signer, Contract, Event } from "ethers";
import { ethers, deployments } from "hardhat";
// eslint-disable-next-line node/no-missing-import
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
    let vrfCoordinator: Contract;

    let beatboxers: { addresses: string[]; names: string[] };

    beforeEach(async () => {
        await deployments.fixture(["mocks", "all"]);
        [deployer, competitionCreator, judgeOne, judgeTwo] =
            await ethers.getSigners();
        competitionName = ethers.utils.formatBytes32String("BBU");
        competitionDescription = "Beatbox competition";
        imageURI = "ipfs://hash";
        beatboxers = await generateRandomBeatboxers();
        vrfCoordinator = await ethers.getContract("VRFCoordinatorV2Mock");
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
        const subscriptionTx = await vrfCoordinator.createSubscription();
        const subscription = await subscriptionTx.wait();
        const subId = subscription.events?.find(
            (e: any) => e.event === "SubscriptionCreated"
        )?.args?.subId;
        let tx = await vrfCoordinator.fundSubscription(
            subId,
            ethers.utils.parseEther("100")
        );
        await tx.wait();
        const beatboxTx = await competitionFactory
            .connect(competitionCreator)
            .createCompetition(
                competitionName,
                competitionDescription,
                imageURI
            );
        let receipt = await beatboxTx.wait();
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
        await deployer.sendTransaction({
            to: beatboxCompetition.address,
            value: ethers.utils.parseEther("1"),
        });
        const setSubscriptionTx = await beatboxCompetition.setSubscriptionId(
            subId
        );
        await setSubscriptionTx.wait();
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

        const addBeatboxersTx = await beatboxCompetition
            .connect(competitionCreator)
            .addBeatboxers(beatboxers.addresses, beatboxers.names);
        const addBeatboxersReceipt = await addBeatboxersTx.wait();
        const requestId = addBeatboxersReceipt.events?.find(
            (e: any) => e.event === "RandomNumberRequested"
        )?.args?.requestId;

        tx = await vrfCoordinator!.fulfillRandomWords(
            requestId,
            beatboxCompetition.address
        );
        receipt = await tx.wait();
        // console.log(receipt);
        expect(
            receipt.events.find((e: any) => e.event === "RandomWordsFulfilled")
                .args.success
        ).to.equal(true);
        expect((await beatboxCompetition.getCurrentOpponents()).length).equals(8);
        const battleStartTime = Math.floor(new Date().getTime() / 1000);
        const battleEndTime = battleStartTime + 24 * 60 * 60; // 1 day
        const winningAmount = ethers.utils.parseEther("0.1");
        const battleTx = await beatboxCompetition.startBattle(
            0,
            "Helium vs. Inertia",
            ethers.utils.formatBytes32String("dQw4w9WgXcQ").slice(0, 24),
            ethers.utils.formatBytes32String("dQw4w9WgXcQ").slice(0, 24),
            battleStartTime,
            battleEndTime,
            winningAmount
        );
        await battleTx.wait();
        await expect(battleTx)
            .to.emit(beatboxCompetition, "BattleCreated")
            .withArgs(0, "Helium vs. Inertia", 3);
        await expect(
            beatboxCompetition.startBattle(
                0,
                "Helium vs. Inertia",
                ethers.utils.formatBytes32String("dQw4w9WgXcQ").slice(0, 24),
                ethers.utils.formatBytes32String("dQw4w9WgXcQ").slice(0, 24),
                battleStartTime,
                battleEndTime,
                winningAmount
            )
        ).to.be.revertedWith("Battle already started");
    });
});
