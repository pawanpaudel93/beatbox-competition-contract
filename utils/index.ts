import crypto from "crypto";


export function generateRandomBeatboxers() {
    const addresses: string[] = [];
    const names: string[] = [];
    for (let i = 0; i < 16; i++) {
        const address = "0x" + crypto.randomBytes(20).toString("hex");
        names.push("Beatboxer " + i);
        addresses.push(address);
    }
    return {
        addresses,
        names,
    };
}
