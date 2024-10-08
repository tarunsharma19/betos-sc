module betos_addr::betos {
    use aptos_framework::object::{Self, Object, ExtendRef};
    use aptos_framework::signer;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::fungible_asset::{Self, FungibleStore, Metadata};
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::account;
    use aptos_std::simple_map::{Self, SimpleMap};
    use switchboard::aggregator;
    use switchboard::math::{Self, SwitchboardDecimal};

    use std::vector;
    use std::option;
    use std::debug::print;
    use std::string::{Self, utf8};

    const STATUS_SCHEDULED: u8 = 0;
    const STATUS_FINISHED: u8 = 1;
    const STATUS_CANCELLED: u8 = 2;

    const EAGGREGATOR_INFO_EXISTS:u64 = 0;
    const ENO_AGGREGATOR_INFO_EXISTS:u64 = 1;

    const OUTCOME_HOME: u8 = 0;
    const OUTCOME_DRAW: u8 = 1;
    const OUTCOME_AWAY: u8 = 2;

    const ASSET_NAME: vector<u8> = b"Betos Token";
    const ASSET_SYMBOL: vector<u8> = b"BET";

    struct Markets has key {
        _id : SimpleMap<u64 , Market>,
    }

    struct Market has key, store {
        admin: address,
        fixture_id: u64,
        status: u8,
        predictions: vector<Prediction>,
        expiry: u64,
    }

    struct Prediction has store, drop {
        user: address,
        fixture_id: u64,
        outcome: u8,
        wager: u64,
        odds: u64,  // Odds specific to this prediction
    }

    struct Rewards has key {
        _id: SimpleMap<u64 , vector<Reward>>,
    }

    struct Reward has key, store, drop {
        user: address,
        amount: u64,
    }

    struct AggregatorInfo has copy, drop, store, key {
        aggregator_addr: address,
        latest_result: u128,
        latest_result_decimal: u8,
        min_response: u128,
        max_response: u128,
    }

    struct Fixture has key {
        _id : SimpleMap<u64 , FixtureData>,
    }

    struct FixtureData has copy,drop,store {
        home: address,
        draw: address,
        away: address,
    }

    // add AggregatorInfo resource with latest value + aggregator address
    /// Logs or updates the AggregatorInfo resource with the latest value from the aggregator.
    public entry fun log_aggregator_info(
        account: &signer,
        aggregator_addr: address
    ) acquires AggregatorInfo {
        // Get the latest value from the aggregator
        let (value, dec, _neg) = math::unpack(aggregator::latest_value(aggregator_addr)); 
        let (min_value, min_dec, min_neg) = math::unpack(aggregator::lastest_round_min_response(aggregator_addr)); 
        let (max_value, max_dec, max_neg) = math::unpack(aggregator::lastest_round_max_response(aggregator_addr)); 

        let min = min_value/1000000000;
        let max = max_value/1000000000;

        // Check if AggregatorInfo exists
        if (exists<AggregatorInfo>(signer::address_of(account))) {
            // Borrow the existing AggregatorInfo and update it
            let aggregator_info = borrow_global_mut<AggregatorInfo>(signer::address_of(account));
            aggregator_info.latest_result = value;
            aggregator_info.latest_result_decimal = dec;
            aggregator_info.min_response = min;
            aggregator_info.max_response = max;
        } else {
            // Create a new AggregatorInfo resource
            move_to(account, AggregatorInfo {
                aggregator_addr: aggregator_addr,
                latest_result: value,
                latest_result_decimal: dec,
                min_response: min,
                max_response: max,
            });
        }
    }

    public entry fun set_oracle_addresses(
        admin: &signer,
        fixture_id: u64,
        outcome: u8,
        oracle_address: address
    ) acquires Fixture {
        assert!(signer::address_of(admin) == @betos_addr, 102);
        if (!exists<Fixture>(@betos_addr)) {
            let _fixture:SimpleMap<u64,FixtureData> = simple_map::create();
            move_to(admin,Fixture{_id:_fixture});
        };

        // Check if the fixture already exists in the Fixture resource
        let fixture = borrow_global_mut<Fixture>(@betos_addr);
        // If the fixture_id already exists in the Fixture map, update the FixtureData.
        // Otherwise, create a new FixtureData and insert it into the Fixture map.
        if (simple_map::contains_key(&fixture._id, &fixture_id)) {
            let fixture_data = simple_map::borrow_mut(&mut fixture._id, &fixture_id);
            if (outcome == OUTCOME_HOME) {
                fixture_data.home = oracle_address;
            } else if (outcome == OUTCOME_DRAW) {
                fixture_data.draw = oracle_address;
            } else if (outcome == OUTCOME_AWAY) {
                fixture_data.away = oracle_address;
            } else {
                abort 102; // Invalid outcome, should be one of OUTCOME_HOME, OUTCOME_DRAW, or OUTCOME_AWAY
            }
        } else {
            // If the fixture does not exist, create a new FixtureData entry
            let new_fixture_data = FixtureData {
                home: if (outcome == OUTCOME_HOME) { oracle_address } else { @0x0 },
                draw: if (outcome == OUTCOME_DRAW) { oracle_address } else { @0x0 },
                away: if (outcome == OUTCOME_AWAY) { oracle_address } else { @0x0 },
            };
            simple_map::add(&mut fixture._id, fixture_id, new_fixture_data);
        }
    }

    fun get_oracle_address(
        fixture: &Fixture,
        fixture_id: u64,
        outcome: u8
    ): address  {
        // Retrieve the FixtureData for the given fixture_id
        let fixture_data = simple_map::borrow(&fixture._id,&fixture_id);

        // Return the oracle address based on the outcome
        if (outcome == OUTCOME_HOME) {
            return fixture_data.home
        } else if (outcome == OUTCOME_DRAW) {
            return fixture_data.draw
        } else if (outcome == OUTCOME_AWAY) {
            return fixture_data.away
        } else {
            return @0x0
        }
    }


    fun init_module(deployer: &signer) {
        // Create the fungible asset metadata object. 
        let constructor_ref = &object::create_named_object(deployer, ASSET_SYMBOL);
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            option::none(),
            utf8(ASSET_NAME), 
            utf8(ASSET_SYMBOL), 
            8, 
            utf8(b"http://example.com/favicon.ico"), 
            utf8(b"http://example.com"), 
        );
    }

    /// Creates a new betting market
    public entry fun create_market(
        admin: &signer,
        fixture_id: u64,
        expiry: u64
    ) acquires Markets
    {
        assert!(signer::address_of(admin) == @betos_addr, 102);

        if (!exists<Markets>(@betos_addr)) {
            let _market:SimpleMap<u64,Market> = simple_map::create();
            move_to(admin,Markets{_id:_market});
        };

        let markets = borrow_global_mut<Markets>(@betos_addr);

        if (simple_map::contains_key(&markets._id, &fixture_id)) {
            let market_data = simple_map::borrow_mut(&mut markets._id, &fixture_id);
            market_data.admin = @betos_addr;
            market_data.fixture_id = fixture_id;
            market_data.status = STATUS_SCHEDULED;
            market_data.predictions= vector::empty<Prediction>();
            market_data.expiry= expiry;
        }
        else{
            let new_market = Market {
            admin: @betos_addr,
            fixture_id,
            status: STATUS_SCHEDULED,
            predictions: vector::empty<Prediction>(),
            expiry,
            };
            simple_map::add(&mut markets._id, fixture_id, new_market);
        };

        
    }

    /// Allows a user to place a prediction on an existing market
  
    public entry fun place_prediction(
        user: &signer,
        admin: address,
        fixture_id: u64,
        outcome: u8,
        wager: u64
    ) acquires Markets, Fixture {

        let market = borrow_global_mut<Markets>(@betos_addr);
        let market_data = simple_map::borrow_mut(&mut market._id,&fixture_id);
        
        assert!(market_data.status == STATUS_SCHEDULED, 101);

        // Retrieve the fixture data from the Fixture resource
        let fixture = borrow_global<Fixture>(@betos_addr);

        // Get the oracle address for the given fixture_id and outcome
        let oracle_address = get_oracle_address(fixture, fixture_id, outcome);

        // Call the oracle to get the odds using the log_aggregator_info function
        let (odds, _, _) = math::unpack(aggregator::latest_value(oracle_address));

        // Verify that the user is sending the exact amount of APT as wager
        let coin = coin::withdraw<AptosCoin>(user, wager);
        coin::deposit(@betos_addr, coin);

        let odd:u64 = (odds * 100 as u64) / 1000_000_000;
        // Store the prediction with the fetched odds
        let prediction = Prediction {
            user: signer::address_of(user),
            fixture_id,
            outcome,
            wager,
            odds: odd ,  // Adjusting odds by dividing by 10^9
        };
        vector::push_back(&mut market_data.predictions, prediction);
    }
    


    /// Resolves a market and calculates rewards
    public entry fun resolve_market(
        admin: &signer,
        fixture_id: u64,
        status: u8,
        result: u8
    ) acquires Markets {
        let market = borrow_global_mut<Markets>(@betos_addr);
        let market_data = simple_map::borrow_mut(&mut market._id,&fixture_id);

        assert!(signer::address_of(admin) == market_data.admin, 102);
        assert!(market_data.status == STATUS_SCHEDULED, 103);

        market_data.status = status;

        if (status == STATUS_FINISHED) {
            let len = vector::length(&market_data.predictions);
            let i = 0;
            while (i < len) {
                let prediction = vector::borrow(&market_data.predictions, i);
                if (prediction.outcome == result) {
                    let reward_amount = calculate_reward(prediction.wager, prediction.odds);
                    let reward = Reward {
                        user: prediction.user,
                        amount: reward_amount,
                    };
                    move_to(admin, reward);
                };
                i = i + 1;
            }
        }
    }
    /// Resolves a market and calculates rewards
    public entry fun resolve_market2(
        admin: &signer,
        fixture_id: u64,
        status: u8,
        result: u8
    ) acquires Markets, Rewards {
        let market = borrow_global_mut<Markets>(@betos_addr);
        let market_data = simple_map::borrow_mut(&mut market._id, &fixture_id);

        assert!(signer::address_of(admin) == market_data.admin, 102);
        assert!(market_data.status == STATUS_SCHEDULED, 103);

        market_data.status = status;

        if (!exists<Rewards>(@betos_addr)) {
            // Create the Rewards resource if it doesn't exist
            let _reward_map: SimpleMap<u64, vector<Reward>> = simple_map::create();
            move_to(admin, Rewards{_id: _reward_map});
        };

        let rewards = borrow_global_mut<Rewards>(@betos_addr);

        if (!simple_map::contains_key(&rewards._id, &fixture_id)) {
            // Create a new rewards vector for the fixture_id if it doesn't exist
            let new_rewards_vector = vector::empty<Reward>();
            simple_map::add(&mut rewards._id, fixture_id, new_rewards_vector);
        };

        let rewards_vector = simple_map::borrow_mut(&mut rewards._id, &fixture_id);

        if (status == STATUS_FINISHED) {
            let len = vector::length(&market_data.predictions);
            let i = 0;
            while (i < len) {
                let prediction = vector::borrow(&market_data.predictions, i);
                if (prediction.outcome == result) {
                    let reward_amount = calculate_reward(prediction.wager, prediction.odds);
                    let reward = Reward {
                        user: prediction.user,
                        amount: reward_amount,
                    };
                    vector::push_back(rewards_vector, reward);
                };
                i = i + 1;
            }
        }
    }


    /// Distributes APT tokens as rewards
    public entry fun distribute_rewards(admin: &signer) acquires Reward {
        assert!(signer::address_of(admin) == @betos_addr, 102);
        let admin_address = signer::address_of(admin);
        let rewards = borrow_global_mut<Reward>(admin_address);
        let reward_amount = rewards.amount;

        coin::transfer<AptosCoin>(admin, rewards.user, reward_amount);

        // Remove the reward entry
        move_from<Reward>(admin_address);
    }

    public entry fun distribute_rewards2(admin: &signer, fixture_id: u64) 
    acquires Rewards 
    {
        assert!(signer::address_of(admin) == @betos_addr, 102);

        // Ensure the Rewards resource exists
        let rewards = borrow_global_mut<Rewards>(@betos_addr);

        // Check if the fixture_id has an associated rewards vector
        if (!simple_map::contains_key(&rewards._id, &fixture_id)) {
            abort 103; // No rewards found for the given fixture_id
        };

        let rewards_vector = simple_map::borrow_mut(&mut rewards._id, &fixture_id);

        let len = vector::length(rewards_vector);
        let i = 0;
        while (i < len) {
            let reward = vector::borrow(rewards_vector, i);
            coin::transfer<AptosCoin>(admin, reward.user, reward.amount);
            i = i + 1;
        };

        // Once all rewards are distributed, remove the rewards vector for the fixture_id
        simple_map::remove(&mut rewards._id, &fixture_id);
    }

    /// Allows a user to withdraw their winnings
    public entry fun withdraw_winnings(user: &signer) acquires Reward {
        let reward = borrow_global_mut<Reward>(@betos_addr);
        let amount = reward.amount;
        coin::transfer<AptosCoin>(user, signer::address_of(user), amount);
        move_from<Reward>(signer::address_of(user));
    }

    /// Calculates the reward based on the wager and odds
    fun calculate_reward(wager: u64, odds: u64): u64 {
        (wager * odds)/100
    }

    
    #[test(admin = @0x123, user1 = @0x456, user2 = @0x789)]
    public entry fun test_betting_flow(admin: signer, user1: signer, user2: signer) 
    // acquires 
    // Market  
    // Reward
    {
        let admin_address = signer::address_of(&admin);
        let user1_address = signer::address_of(&user1);
        init_module(&admin);
        init_module(&user1);
        // Create accounts for admin, user1, and user2 for the test
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user1_address);
        // account::create_account_for_test(signer::address_of(&user1));
        // account::create_account_for_test(signer::address_of(&user2));
        // aptos_coin::publish_store(&admin);
        // Initialize contract with admin account
        create_market(&admin, 1, 86400); // Market expiry set to 1 day in seconds
        //to pass our aptos coin balance assertion
        // aptos_coin::deposit(admin_address, aptos_coin::mint_apt_fa_for_test(1001));
        // aptos_coin::deposit(user1_address, aptos_coin::mint_apt_fa_for_test(1001));
        primary_fungible_store::deposit(admin_address, aptos_coin::mint_apt_fa_for_test(1001));
        primary_fungible_store::deposit(user1_address, aptos_coin::mint_apt_fa_for_test(1001));
        // aptos_coin::mint_apt_fa_for_test(amount)
        // Admin places a bet on OUTCOME_HOME
        // place_prediction(
        //     admin_address,  // Admin's address
        //     &user1,                      // Admin's signer
        //     1,                           // Fixture ID
        //     OUTCOME_HOME,                // Outcome
        //     1,                         // Wager
        //     2                            // Odds
        // );
        
        // User1 places a bet on OUTCOME_HOME
        // place_prediction(
        //     admin_address,  // Admin's address (same market)
        //     &user1,                      // User1's signer
        //     1,                           // Fixture ID
        //     OUTCOME_HOME,                // Outcome
        //     150,                         // Wager
        //     250                          // Odds
        // );
        
        // Fetch the market to verify the predictions
        // let market = borrow_global<Market>(admin_address);
        
        // let prediction_admin = vector::borrow(&market.predictions, 0);
        // assert!(prediction_admin.user == admin_address, 5);
        // assert!(prediction_admin.outcome == OUTCOME_HOME, 6);
        
        // let prediction_user1 = vector::borrow(&market.predictions, 1);
        // assert!(prediction_user1.user == signer::address_of(&user1), 7);
        // assert!(prediction_user1.outcome == OUTCOME_HOME, 8);
        
        // // Resolve the market with OUTCOME_HOME as the result
        // resolve_market(&admin, 1, STATUS_FINISHED, OUTCOME_HOME);
        
        // // Verify reward allocation
        // let reward_admin = borrow_global<Reward>(admin_address);
        // assert!(reward_admin.amount == 200, 11); // Admin's reward: (100 * 2) / 100 = 200
        
        // let reward_user1 = borrow_global<Reward>(signer::address_of(&user1));
        // assert!(reward_user1.amount == 375, 12); // User1's reward: (150 * 2.5) / 100 = 375
        
        // // Distribute rewards
        // distribute_rewards(&admin);

        // log_aggregator_info(&admin,0x7457731ac96b5943d01f3f1ce1fe739b53ebc5aeec45432afa169515b9f7eb1b);

        // Admin and User1 withdraw their winnings
        // withdraw_winnings(&admin);
        // withdraw_winnings(&user1);
    }
}
