import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { CompetitionFactory as CompetitionFactoryContract } from "./../typechain";

describe("CompetitionFactory", function () {
    let competitionFactory: CompetitionFactoryContract;

    beforeEach(async () => {
        await deployments.fixture(["all"]);
        const [deployer] = await ethers.getSigners();
        competitionFactory = await ethers.getContract(
            "CompetitionFactory",
            deployer
        );
    });

    it("Should deploy and create a beatbox competition contract", async function () {
        const beatboxTx = await competitionFactory.createCompetition("Beatbox");
        const receipt = await beatboxTx.wait();
        expect(receipt)
            .to.emit(competitionFactory, "CompetitionCreated")
            .withArgs(0, "Beatbox");
    });
});
