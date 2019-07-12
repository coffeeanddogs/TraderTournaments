pragma solidity 0.5.0;
import "github.com/oraclize/ethereum-api/oraclizeAPI.sol";

// ----------------------------------------------------------------------------
// Safe maths
// ----------------------------------------------------------------------------
library SafeMath {
    function add(uint a, uint b) internal pure returns (uint c) {
        c = a + b;
        require(c >= a);
    }
    function sub(uint a, uint b) internal pure returns (uint c) {
        require(b <= a);
        c = a - b;
    }
    function mul(uint a, uint b) internal pure returns (uint c) {
        c = a * b;
        require(a == 0 || c / a == b);
    }
    function div(uint a, uint b) internal pure returns (uint c) {
        require(b > 0);
        c = a / b;
    }
}

contract Factory {
    // emit the address of the tournament
    event contractCreated(address newAddress);
    // function to create a Tournament
    function createToken(string memory _name, string memory _asset, uint256 _prediction_cost, uint256 time_to_start_minutes, uint256 duration_minutes) public returns (Predictor tokenAddress) {
        address payable creator = msg.sender; 
        Predictor Tournament = new Predictor(_name, _asset, _prediction_cost, time_to_start_minutes, duration_minutes, creator);
        emit contractCreated(address(Tournament));
        return Tournament;
    }
}

contract Predictor is usingOraclize {
    using SafeMath for uint;
    
    // INITIATE TIME
    uint256 public competition_duration;
    uint256 public price_prediction_period;
    uint256 public resolution_period;
    
    // DATA 
    address payable trader_tournaments = 0xb8fD4510478debe4Ce027cFbEEA3a6fb17A80046;
    address payable tournament_creator;
    uint256 fee_rate_percent;
    bool public fee_collected = false;
    bool public price_has_settled = false;
    mapping(address => uint256) public balance;
    mapping(address => bool) public player_has_withdrew;
    mapping(address => uint256) public players_total_stake;
    mapping(address => uint256[]) public positions;
    mapping(address => uint256) public prediction_number;
    mapping(address => uint256) public predicted_price;
    uint256 public cost_to_predict;
    uint256 public winning_distance;
    uint256 public winners;
    uint256 public total_prediction_stake_pool;
    uint256 public winning_prediction;
    uint256 public test;
    bool winner_set = false;
    string public name;
    string public asset;
        
    constructor (string memory _name, string memory _asset, uint256 prediction_cost, uint256 time_to_start_minutes, uint256 duration_minutes, address payable _creator) public {
        name = _name;
        asset = _asset;
        fee_rate_percent = 2;
        cost_to_predict = prediction_cost;
        tournament_creator = _creator;
        // INITIATE time and Call the settlement price
        price_prediction_period = now + (time_to_start_minutes * 1 minutes);
        competition_duration = now + (time_to_start_minutes * 1 minutes) + (duration_minutes * 1 minutes);
        resolution_period = now + (time_to_start_minutes * 1 minutes) + (duration_minutes * 1 minutes) + 24 hours;
        oraclize_query(competition_duration, "URL", "json(https://api.pro.coinbase.com/products/ETH-USD/ticker).price");
         
    }
  
    // ORACLIZE
    string public ETHUSD;
    function __callback(bytes32 myid, string memory result) public {
        // make sure the caller is the oracle    
        if (msg.sender != oraclize_cbAddress()) revert();
        ETHUSD = result;
        // mark that the price has been settled
        price_has_settled = true;
    }
    
    function predict(uint256 _prediction_price) external payable {
        // make sure the correct amount of eth is sent to predict
        require(msg.value == cost_to_predict, "Please send the correct cost to predict!");
        // make sure the tournament has not started
        require(now < price_prediction_period, "Whoops! It is not the price prediction period!");
        address customer = msg.sender;
        // credit the address with the prediction
        positions[customer].push(_prediction_price);
        prediction_number[customer] = SafeMath.add(prediction_number[customer], 1);
        // increment total stake
        total_prediction_stake_pool = SafeMath.add(total_prediction_stake_pool, cost_to_predict);
        // increment the players total stake 
        players_total_stake[customer] = SafeMath.add(players_total_stake[customer], cost_to_predict);
        
    }
    
    function claim_winning_prediction(uint256 pos_number) external {
        // make sure it is the resolution period
        require(now > competition_duration);
        require(now < resolution_period, "Sorry");
        // data
        address customer = msg.sender;
        uint256 prediction = SafeMath.mul(positions[customer][pos_number], 100);
        uint256 distance;
        uint256 eth_price = SafeMath.mul(safeParseInt(ETHUSD, 2), 100);

        // calculate distance
        if (prediction > eth_price) {
            distance = SafeMath.div(SafeMath.sub(prediction, eth_price), 100);
        }
        if (prediction < eth_price) {
            distance = SafeMath.div(SafeMath.sub(eth_price, prediction), 100);
        }
        if (prediction == eth_price) {
            distance = 0;
        }
        if (!winner_set) {
            winner_set = true; 
            winning_distance = distance;
            predicted_price[customer] = prediction;
            winning_prediction = prediction;
            winners = 1;
        }
        // decide if winner
        if (winning_distance > distance) {
            // assign customer distance as the winning distance
            winning_distance = distance;
            // update winning prediction
            winning_prediction = prediction;
            // reset number of winners
            winners = 1;
            predicted_price[customer] = prediction;
        }
        // If tied
        if (winning_distance == distance && predicted_price[customer] != prediction) {
            // increment the current number of winners
            winners++;
            predicted_price[customer] = prediction;
        }
    }
    
    function collect_my_winnings() external {
        // make sure resolution period is over
        require(now > resolution_period, "Sorry! It is not the appropriate time to collect!");
        require(player_has_withdrew[msg.sender] != true, "This address has already withdrawn");
        address payable customer = msg.sender;
        uint256 winnings;
        uint256 _fee;
        uint256 value_to_transfer;
        
        // check if player distance is the winning distance
        if (predicted_price[customer] == winning_prediction) {
            // Mark the customer as been paid out
            player_has_withdrew[customer] = true;
            // pay the customer minus fees
            winnings = SafeMath.div(total_prediction_stake_pool, winners);
            _fee = SafeMath.div(SafeMath.mul(winnings, fee_rate_percent), 100);
            value_to_transfer = SafeMath.sub(winnings, _fee);
            customer.transfer(value_to_transfer);
        } else {
            revert("Sorry!");
        }
    }

    function collect_fees() external {
        require(now > resolution_period, "The game is not over!");
        require(price_has_settled == true, "The price has not settled!");
        require(fee_collected != true, "The fee has been collected!");
        // calculate fee to send
        uint256 fee_to_credit = SafeMath.div(SafeMath.div(SafeMath.mul(total_prediction_stake_pool, fee_rate_percent), 100), 2);
        fee_collected = true;
        balance[trader_tournaments] = fee_to_credit;
        balance[tournament_creator] = fee_to_credit;
    }
    
    function withdraw_fees() external {
        uint256 _balance = balance[msg.sender];
        balance[msg.sender] = 0;
        msg.sender.transfer(_balance);
    }
    

    function the_game_broke() external {
        
        require(now > resolution_period, "The game is not over!");
        require(price_has_settled == false, "The price has settled!");
        address payable customer = msg.sender;
        require(player_has_withdrew[customer] != true, "This address has already withdrawn");
        
        // Mark the customer as been paid out
        player_has_withdrew[customer] = true;
        // Return customers staked ETH
        balance[customer] = players_total_stake[customer];
    }

    // fallback
    function () external payable {
        revert();
    }
}
