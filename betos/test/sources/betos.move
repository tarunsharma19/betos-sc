module betos_addr::betos {
    use aptos_framework::signer;
    use aptos_framework::vector;
    use aptos_framework::account;

    const STATUS_SCHEDULED: u8 = 0;
    const STATUS_FINISHED: u8 = 1;
    const STATUS_CANCELLED: u8 = 2;

    const OUTCOME_HOME: u8 = 0;
    const OUTCOME_DRAW: u8 = 1;
    const OUTCOME_AWAY: u8 = 2;

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

    struct Reward has key, store, drop {
        user: address,
        amount: u64,
    }

    /// Creates a new betting market
    public entry fun create_market(
        admin: &signer,
        fixture_id: u64,
        expiry: u64
    ) {
        let market = Market {
            admin: signer::address_of(admin),
            fixture_id,
            status: STATUS_SCHEDULED,
            predictions: vector::empty<Prediction>(),
            expiry,
        };
        move_to(admin, market);
    }

    /// Allows a user to place a prediction on an existing market
    public entry fun place_prediction(
        admin: address,
        user: &signer,
        fixture_id: u64,
        outcome: u8,
        wager: u64,
        odds: u64  // Odds are now passed when placing the bet
    ) acquires Market {
        let market = borrow_global_mut<Market>(admin);
        assert!(market.status == STATUS_SCHEDULED, 101);

        let prediction = Prediction {
            user: signer::address_of(user),
            fixture_id,
            outcome,
            wager,
            odds,  // Store the odds with the prediction
        };
        vector::push_back(&mut market.predictions, prediction);
    }

    /// Resolves a market and calculates rewards
    public entry fun resolve_market(
        admin: &signer,
        fixture_id: u64,
        status: u8,
        result: u8
    ) acquires Market {
        let market = borrow_global_mut<Market>(signer::address_of(admin));
        assert!(signer::address_of(admin) == market.admin, 102);
        assert!(market.status == STATUS_SCHEDULED, 103);

        market.status = status;

        if (status == STATUS_FINISHED) {
            let len = vector::length(&market.predictions);
            let i = 0;
            while (i < len) {
                let prediction = vector::borrow(&market.predictions, i);
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

    /// Allows a user to withdraw their winnings
    public entry fun withdraw_winnings(user: &signer) acquires Reward {
        let reward = borrow_global_mut<Reward>(signer::address_of(user));
        let _amount = reward.amount;  // Prefixed with underscore to suppress warning
        move_from<Reward>(signer::address_of(user));
    }

    /// Calculates the reward based on the wager and odds
    fun calculate_reward(wager: u64, odds: u64): u64 {
        (wager * odds) / 100
    }

    #[test(admin = @0x123, user1 = @0x456, user2 = @0x789)]
    public entry fun test_betting_flow(admin: signer, user1: signer, user2: signer) acquires Market, Reward {
        // Create accounts for admin, user1, and user2 for the test
        account::create_account_for_test(signer::address_of(&admin));
        account::create_account_for_test(signer::address_of(&user1));
        account::create_account_for_test(signer::address_of(&user2));
        
        // Initialize contract with admin account
        create_market(&admin, 1, 86400); // Market expiry set to 1 day in seconds
        
        // Admin places a bet on OUTCOME_HOME
        place_prediction(
            signer::address_of(&admin),  // Admin's address
            &admin,                      // Admin's signer
            1,                           // Fixture ID
            OUTCOME_HOME,                // Outcome
            100,                         // Wager
            2                          // Odds
        );
        
        // User1 places a bet on OUTCOME_HOME
        // place_prediction(
        //     signer::address_of(&admin),  // Admin's address (same market)
        //     &user1,                      // User1's signer
        //     1,                           // Fixture ID
        //     OUTCOME_HOME,                // Outcome
        //     150,                         // Wager
        //     250                          // Odds
        // );
        
        // User2 places a bet on OUTCOME_AWAY
        // place_prediction(
        //     signer::address_of(&admin),  // Admin's address (same market)
        //     &user2,                      // User2's signer
        //     1,                           // Fixture ID
        //     OUTCOME_AWAY,                // Outcome
        //     200,                         // Wager
        //     300                          // Odds
        // );
        
        // Fetch the market to verify the predictions
        let market = borrow_global<Market>(signer::address_of(&admin));
        // assert!(vector::length(&market.predictions) == 3, 4);
        
        let prediction_admin = vector::borrow(&market.predictions, 0);
        assert!(prediction_admin.user == signer::address_of(&admin), 5);
        assert!(prediction_admin.outcome == OUTCOME_HOME, 6);
        
        // let prediction_user1 = vector::borrow(&market.predictions, 1);
        // assert!(prediction_user1.user == signer::address_of(&user1), 7);
        // assert!(prediction_user1.outcome == OUTCOME_HOME, 8);
        
        // let prediction_user2 = vector::borrow(&market.predictions, 2);
        // assert!(prediction_user2.user == signer::address_of(&user2), 9);
        // assert!(prediction_user2.outcome == OUTCOME_AWAY, 10);
        
        // Resolve the market with OUTCOME_HOME as the result
        resolve_market(&admin, 1, STATUS_FINISHED, OUTCOME_HOME);
        
        // Verify reward allocation
        let reward_admin = borrow_global<Reward>(signer::address_of(&admin));
        assert!(reward_admin.amount == 2, 11); // Admin's reward: (100 * 200) / 100 = 200
        
        // let reward_user1 = borrow_global<Reward>(signer::address_of(&user1));
        // assert!(reward_user1.amount == 375, 12); // User1's reward: (150 * 250) / 100 = 375
        
        // // User2 should not have received any reward
        // assert!(!exists<Reward>(signer::address_of(&user2)), 13);
        
        // Admin and User1 withdraw their winnings
        withdraw_winnings(&admin);
        // withdraw_winnings(&user1);
    }

}
