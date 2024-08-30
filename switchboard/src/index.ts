import { Buffer } from "buffer";
// import { AptosClient, AptosAccount, FaucetClient, HexString } from "aptos";
import {
  AptosEvent,
  EventCallback,
  OracleJob,
  createFeed,
} from "@switchboard-xyz/aptos.js";
import { Account, Aptos, AptosConfig, Ed25519PrivateKey } from "@aptos-labs/ts-sdk";

const NODE_URL = "https://fullnode.testnet.aptoslabs.com/v1";
const FAUCET_URL = "https://faucet.testnet.aptoslabs.com";

const SWITCHBOARD_ADDRESS =
  "0x34e2eead0aefbc3d0af13c0522be94b002658f4bef8e0740a21086d22236ad77";

const SWITCHBOARD_QUEUE_ADDRESS =
  "0x34e2eead0aefbc3d0af13c0522be94b002658f4bef8e0740a21086d22236ad77";

const SWITCHBOARD_CRANK_ADDRESS =
  "0x34e2eead0aefbc3d0af13c0522be94b002658f4bef8e0740a21086d22236ad77";

const client = new AptosConfig({fullnode:NODE_URL});
// const faucetClient = new FaucetClient(NODE_URL, FAUCET_URL);
export const aptos = new Aptos(client);

// Create new user
let pk = new Ed25519PrivateKey("0x5a0fa5377c25b0187bffa20d577715c53067c6d929e261343e7915da849f266d"!)
const alice = Account.fromPrivateKey({privateKey:pk})
 
    
// const fundacc = async () =>{
//   console.log("called")
//   const transaction = await aptos.transferCoinTransaction({
//     sender: alice.accountAddress,
//     recipient: accountAddress,
//     amount: 1_000_000,
//   });
//   const pendingTxn = await aptos.signAndSubmitTransaction({
//     signer: alice,
//     transaction,
//   });

async function main() {
  // fundacc()
  console.log(`User account ${alice.accountAddress} created + funded.`);

  // Make Job data for BTC price
  const serializedJob = Buffer.from(
    OracleJob.encodeDelimited(
      OracleJob.create({
        tasks: [
          {
            httpTask: {
              url: "https://data-server-aptos.onrender.com/odds/1268085",
            },
          },
          {
            jsonParseTask: {
              path: "$.home",
            },
          },
        ],
      })
    ).finish()
  );

  const [aggregator, createFeedTx] = await createFeed(
    aptos,
    alice,
    {
      authority: alice.accountAddress,
      queueAddress: SWITCHBOARD_QUEUE_ADDRESS, // account with OracleQueue resource
      crankAddress: SWITCHBOARD_CRANK_ADDRESS, // account with Crank resource
      batchSize: 1, // number of oracles to respond to each round
      minJobResults: 1, // minimum # of jobs that need to return a result
      minOracleResults: 1, // minumum # of oracles that need to respond for a result
      minUpdateDelaySeconds: 5, // minimum delay between rounds
      coinType: "0x1::aptos_coin::AptosCoin", // CoinType of the queue (now only AptosCoin)
      initialLoadAmount: 10_000_000, // load of the lease
      jobs: [
        {
          name: "BTC/USD",
          metadata: "binance",
          authority: alice.accountAddress,
          data: serializedJob.toString("base64"), // jobs need to be base64 encoded strings
          weight: 1,
        },
      ],
    },
    SWITCHBOARD_ADDRESS
  );

  console.log(
    `Created Aggregator and Lease resources at account address ${aggregator.address}. Tx hash ${createFeedTx}`
  );

  // Manually trigger an update
  await aggregator.openRound(alice);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
