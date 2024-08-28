"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const buffer_1 = require("buffer");
const aptos_1 = require("aptos");
const aptos_js_1 = require("@switchboard-xyz/aptos.js");
const NODE_URL = "https://fullnode.devnet.aptoslabs.com/v1";
const FAUCET_URL = "https://faucet.devnet.aptoslabs.com";
const SWITCHBOARD_ADDRESS = "0x34e2eead0aefbc3d0af13c0522be94b002658f4bef8e0740a21086d22236ad77";
const SWITCHBOARD_QUEUE_ADDRESS = "0x34e2eead0aefbc3d0af13c0522be94b002658f4bef8e0740a21086d22236ad77";
const SWITCHBOARD_CRANK_ADDRESS = "0x34e2eead0aefbc3d0af13c0522be94b002658f4bef8e0740a21086d22236ad77";
const client = new aptos_1.AptosClient(NODE_URL);
const faucetClient = new aptos_1.FaucetClient(NODE_URL, FAUCET_URL);
// create new user
let user = new aptos_1.AptosAccount();
await faucetClient.fundAccount(user.address(), 50000);
console.log(`User account ${user.address().hex()} created + funded.`);
// Make Job data for btc price
const serializedJob = buffer_1.Buffer.from(aptos_js_1.OracleJob.encodeDelimited(aptos_js_1.OracleJob.create({
    tasks: [
        {
            httpTask: {
                url: "https://www.binance.us/api/v3/ticker/price?symbol=BTCUSD",
            },
        },
        {
            jsonParseTask: {
                path: "$.price",
            },
        },
    ],
})).finish());
const [aggregator, createFeedTx] = await (0, aptos_js_1.createFeed)(client, user, {
    authority: user.address(),
    queueAddress: SWITCHBOARD_QUEUE_ADDRESS, // account with OracleQueue resource
    crankAddress: SWITCHBOARD_CRANK_ADDRESS, // account with Crank resource
    batchSize: 1, // number of oracles to respond to each round
    minJobResults: 1, // minimum # of jobs that need to return a result
    minOracleResults: 1, // minumum # of oracles that need to respond for a result
    minUpdateDelaySeconds: 5, // minimum delay between rounds
    coinType: "0x1::aptos_coin::AptosCoin", // CoinType of the queue (now only AptosCoin)
    initialLoadAmount: 1000, // load of the lease
    jobs: [
        {
            name: "BTC/USD",
            metadata: "binance",
            authority: user.address().hex(),
            data: serializedJob.toString("base64"), // jobs need to be base64 encoded strings
            weight: 1,
        },
    ],
}, SWITCHBOARD_ADDRESS);
console.log(`Created Aggregator and Lease resources at account address ${aggregator.address}. Tx hash ${createFeedTx}`);
// Manually trigger an update
await aggregator.openRound(user);
