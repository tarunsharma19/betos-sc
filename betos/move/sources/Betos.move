module 0x1::Betos {
    use 0x1::Signer;
    use 0x1::Vector;
    use 0x1::Address;

    // Define constants for Status
    const STATUS_SCHEDULED: u8 = 0;
    const STATUS_FINISHED: u8 = 1;
    const STATUS_CANCELLED: u8 = 2;

    // Define constants for Outcome
    const OUTCOME_HOME: u8 = 0;
    const OUTCOME_DRAW: u8 = 1;
    const OUTCOME_AWAY: u8 = 2;

    // Define a Market struct
    struct Market has store {
        admin: address,             // Address of the admin who created the market
        fixture_id: u64,            // Unique ID for the fixture (match)
        status: u8,                 // Market status encoded as u8 (0: Scheduled, 1: Finished, 2: Cancelled)
        odds: vector<Odds>,        // List of odds for the different outcomes
        predictions: vector<Prediction>, // List of predictions made by users
        expiry: u64,               // Expiry time for the market
    }

    // Define a Prediction struct
    struct Prediction has store {
        user: address,             // Address of the user who made the prediction
        fixture_id: u64,           // ID of the fixture being predicted
        outcome: u8,               // Predicted outcome encoded as u8 (0: Home, 1: Draw, 2: Away)
        wager: u64,                // Amount wagered by the user
        odds: vector<Odds>,       // Odds for each outcome at the time of betting
    }

    // Define an Odds struct
    struct Odds has store {
        outcome: u8,               // Outcome associated with these odds encoded as u8 (0: Home, 1: Draw, 2: Away)
        value: f64,                // Odds value
    }

    // Define a Reward struct
    struct Reward has store {
        user: address,             // Address of the user receiving the reward
        amount: u64,               // Amount of reward
    }

    // Function to create a new market
    public fun create_market(
        admin: &signer,          // Admin who creates the market
        fixture_id: u64,        // ID of the fixture
        odds: vector<Odds>,    // Initial odds for the fixture
        expiry: u64            // Expiry time for the market
    ) {
        let market = Market {
            admin: Signer::address_of(admin),  // Get admin's address
            fixture_id,                        // Set fixture ID
            status: STATUS_SCHEDULED,          // Initial status is Scheduled (0)
            odds,                              // Set odds
            predictions: Vector::empty<Prediction>(), // Initialize empty predictions list
            expiry,                            // Set expiry time
        };
        move_to(&admin, market);
    }

    // Function to place a prediction on a market
    public fun place_prediction(
        user: &signer,             // User placing the prediction
        fixture_id: u64,          // ID of the fixture
        outcome: u8,              // Predicted outcome (0: Home, 1: Draw, 2: Away)
        wager: u64,               // Amount wagered
        odds: vector<Odds>        // Odds for the prediction
    ) {
        let market = borrow_global_mut<Market>(fixture_id);
        assert!(market.status == STATUS_SCHEDULED, 1); // Ensure the market status is Scheduled (0)
        let prediction = Prediction {
            user: Signer::address_of(user),  // Get user's address
            fixture_id,                      // Set fixture ID
            outcome,                         // Set predicted outcome
            wager,                           // Set wager amount
            odds,                            // Set odds at the time of betting
        };
        Vector::push_back(&mut market.predictions, prediction);
    }

    // Function to resolve the market and distribute rewards
    public fun resolve_market(
        admin: &signer,             // Admin resolving the market
        fixture_id: u64,           // ID of the fixture
        status: u8,               // New status of the market (0: Scheduled, 1: Finished, 2: Cancelled)
        result: u8               // Actual outcome of the fixture (0: Home, 1: Draw, 2: Away)
    ) {
        let market = borrow_global_mut<Market>(fixture_id);
        assert!(Signer::address_of(admin) == market.admin, 2);
        market.status = status;

        if (status == STATUS_FINISHED) { // Market is Finished
            let total_wager: u64 = Vector::iter(&market.predictions)
                .map(|p| p.wager)
                .fold(0, |acc, wager| acc + wager);

            let predictions = Vector::iter(&mut market.predictions).collect::<Vec<_>>();
            for prediction in predictions {
                if prediction.outcome == result {
                    let odds = find_odds(&market.odds, result);
                    let reward_amount = calculate_reward(prediction.wager, odds);
                    let reward = Reward {
                        user: prediction.user,
                        amount: reward_amount,
                    };
                    move_to(&prediction.user, reward);
                }
            }
        }
    }

    // Function to withdraw winnings
    public fun withdraw_winnings(user: &signer) {
        let reward = borrow_global_mut<Reward>(Signer::address_of(user));
        let amount = reward.amount;
        // Code to transfer the amount to user's wallet would go here
        move_from<Reward>(Signer::address_of(user));
    }

    // Function to get market information
    public fun get_market_info(fixture_id: u64): (u8, vector<Odds>, u64) {
        let market = borrow_global<Market>(fixture_id);
        (market.status, market.odds, market.expiry)
    }

    // Function to cancel a prediction
    public fun cancel_prediction(user: &signer, fixture_id: u64) {
        let market = borrow_global_mut<Market>(fixture_id);
        assert!(market.status == STATUS_SCHEDULED, 3);
        let predictions = Vector::iter(&mut market.predictions)
            .filter(|p| p.user == Signer::address_of(user))
            .collect::<Vec<_>>();

        for pred in predictions {
            Vector::remove(&mut market.predictions, pred);
        }
    }

    // Function to check the user's balance
    public fun check_balance(user: &signer): u64 {
        let reward = borrow_global<Reward>(Signer::address_of(user));
        reward.amount
    }

    // Helper function to find odds for a given outcome
    private fun find_odds(odds: &vector<Odds>, outcome: u8): f64 {
        for o in Vector::iter(odds) {
            if o.outcome == outcome {
                return o.value;
            }
        }
        0.0
    }

    // Helper function to calculate reward amount based on wager and odds
    private fun calculate_reward(wager: u64, odds: f64): u64 {
        (wager as f64 * odds) as u64
    }
}
