// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.8.0;

contract StakingChain {
    /*
    *   Each PP is a player that is staked by the network
    *   and their results will be tracked on the blockchain
    *
    *   Code flow:
    *   A player requests a buy_in for a tournament
    *   (Later) Backers choose to buy action (app fee?)
    *   The buy in is given to the player (app fee?)
    *   The contract listens for the tournament result
    *   The contract requests the winnings from the player
    *   The contract pays the backers (app fee?)
    */
    struct PP {
        uint256 pp_id;      // unique id for each player
        uint256 curr_bankroll; // money player is holding that can be used 
        uint256 max_stake;     // highest amount a player can buy into a game with
        bool status;        // whether player can play (hasn't broken bankroll rules)
        bool shot;          // whether player can take shot at one notch higher game
        uint256 in_game;        // state of player, asssuming one game at a time
        address pp_bank;     // address of this pp
        uint256 buyin_requested;   // amount requested by player
        uint256 action_sold;  // amount invested in player
        uint256 markup;     // the fee players will charge on investments in PPM, 1000000 would be at face value
        uint256 tournament_buyin;  // amount of tournament player is playing
        
    }
    
    // mapping(pp => mapping(investor => mapping(tourney => parts p/million (PPM))) action))
    mapping(uint256 => mapping(address => mapping(uint256 => uint256))) public action_owned;   // How much of each player does any address own
    // mapping(pp => results)
    mapping (uint256 => uint256) public total_results; // Tracks results for each play_id 
    // tourney results mapping, updated by owner, from tourney_id => poker player => profit
    // the revenue from tournament bc the buy_in is already paid
    mapping (uint256 => mapping(uint256 => uint256)) public tourney_results;
    
    address public owner;
    // unique id per player
    uint256 public play_id;
    
    // mapping holding all player structs 
    mapping(uint256 => PP) public player_database;
    
    constructor() {
        play_id = 0;
        owner = msg.sender;
    }
    // amountReq is how much of buy_in play_id wants to sell at given markup
    event RequestTourney (uint256 amountReq, uint256 play_id, uint256 buy_in, uint256 tourney_id, uint256 markup);
    // after investor accepts event is emitted so that amountReq can be transferred to player
    event PlayerNeedsFunds (uint256 amountReq, uint256 play_id);
    // event for results emitted by contract owner, player will listen and then distribute if profit >0
    event updateResults(uint256 profit, uint256 tourney_id, uint256 pp_id);
    // event for backers to listen for so they can request their profit to be transferred back to them
    event pickUpProfit(uint256 profit, uint256 tourney_id, uint256 pp_id);
    
    //uint constant PERCENT = 100;
    // a parts per million constant is used to calculate numbers and division of assets with low slippage
    uint256 constant PPM = 1000000;
    
    // register poker players (PP) so they can request tournament investors
    // @param pp_bank: address of each pp_bank
    // @param curr_bankroll: amount player can use to buy-in to a tournament
    // @param max_stake: the highest stake a player can request to play
    // @return: the normalized id for the next PP
    function register_pp(
        address pp_bank, uint256 curr_bankroll, uint256 max_stake)
    public returns (uint256) {
        require(msg.sender == owner, "Only owner can register new players!");
        // Not payable, so currently the same as require(curr_bankroll == 0)
        require(curr_bankroll <= 0, "Insufficient value to add to bankroll!");
        
        player_database[play_id] = PP(
            play_id, 
            curr_bankroll,
            max_stake,
            true,
            false,
            0,
            pp_bank,
            0,
            0,
            0,
            0
        );
        
        // increment id's so that all players are unique
        play_id += 1;
        
        return play_id - 1;
    }
    
    // changes the maximum stake a player can request to play
    function updateMaxStake(uint256 _max_stake, uint256 pp_id) public returns(string memory pp_status) {
        require(msg.sender == owner, "Only owner can update players!");
        player_database[pp_id].max_stake = _max_stake;
        return "Stake updated";
    }
    // player has picked up event on result 
    // self-listening event: after which player will send profits to contract
    // self listening event: [function that is waiting for a specific event to do stuff after]
    // After a tournament is over if there is net profit, the player will transfer the relevant amount back to the contract
    // everyone who invested is listening for results and can manually request 
    // Potential problem: (in case a block fails nobody will get money)
    // update total profit
    function distribute_result(uint256 pp_id, uint256 tourney_id) public payable returns(string memory pp_status) {
        require(action_owned[pp_id][msg.sender][tourney_id] > 0, "You don't own any of that player's action!");
        // total cash of tourney * (1 - app fee) * action_owned(msg.sender)
        uint256 profit = (tourney_results[tourney_id][pp_id] * (1) * action_owned[pp_id][msg.sender][tourney_id])/PPM;
        // require that the profit is correct
        // Alternatively, just calculate the profit ourselves
        // make sure that the money goes to the backers
        address payable backer = payable(msg.sender);
        backer.transfer(profit);
        action_owned[pp_id][msg.sender][tourney_id] = 0;
        return "Profit sent, Balance cleared";
    }
    
    // Emits an event that backers will listen for so they can request their profit to be transferred 
    function accept_results(uint256 pp_id, uint256 tourney_id) public payable returns(string memory){
        require(player_database[pp_id].pp_bank == msg.sender, "sender is wrong");
        require(msg.value == tourney_results[tourney_id][pp_id]*player_database[pp_id].action_sold / PPM, "profit is wrong");
        total_results[pp_id] += msg.value;
        
        // emit an event telling backers to claim their money
        emit pickUpProfit(msg.value, tourney_id, pp_id);
        
        // reset PP fields so they can request to play another tournament
        player_database[pp_id].in_game = 0;
        player_database[pp_id].buyin_requested = 0;
        player_database[pp_id].action_sold = 0;
        player_database[pp_id].markup = 0;
        player_database[pp_id].tournament_buyin = 0;
        
        return "Player sent profit to backer";
    }
    
    // Check if player has funds, otherwise their status goes to inactive and can't play until status is reverted
    //NOTE:  up keep fx not part of normal flow
    // allow owner to blacklist/temp ban a player from chain
    /*function change_status(uint256 pp_id, bool new_status) public returns(string memory pp_status) {
        require(msg.sender == owner);
        
        if(player_database[pp_id].curr_bankroll <= 0) {
            player_database[pp_id].pp_status = false;
            return "Player inactive";
        }
        else {
            return "Player active";
        }
        
    }*/
    
    // Player will emit an event requesting to play a Tourney with a given buy-in
    // amountReq is the amount the player is selling of the total buy_in
    // everything in denominated in wei
    // markup is the fee a player charges on top -  PPM (1000000+) multiplied by action sold; amount player invests in a tourney: (buy_in - amountReq/markup)
    function request_buyin(uint256 pp_id, uint256 amountReq, uint256 buy_in, uint256 tourney_id, uint256 markup) public returns(string memory pp_status) {
        require(msg.sender == player_database[pp_id].pp_bank);
        require(buy_in <= player_database[pp_id].max_stake, "This game is above your max stake");
        require(player_database[pp_id].buyin_requested == 0, "Cannot buy in to multiple games at once");
        require(player_database[pp_id].status, "You are not currently allowed to use this contract.");
        player_database[pp_id].buyin_requested = (amountReq * markup) / PPM;
        player_database[pp_id].markup = markup;
        player_database[pp_id].tournament_buyin = buy_in;
        player_database[pp_id].in_game = tourney_id;
        
        // emit event with details of tournament requested by player
        emit RequestTourney (amountReq, pp_id, buy_in, tourney_id, markup); 
        return "Buy-in requested by player";
    }
    // Backer "responds" to player ReqeustTourney event, interested in investing
    //
    function invest(uint256 amountReq, uint256 pp_id) public payable returns(string memory pp_status){
        require(amountReq <= player_database[pp_id].buyin_requested - player_database[pp_id].curr_bankroll, "Not enough action for sale!");
        player_database[pp_id].curr_bankroll += msg.value;
        
        // total action for sale in PPM
        uint256 action_for_sale = (player_database[pp_id].buyin_requested * PPM) / ((player_database[pp_id].tournament_buyin * player_database[pp_id].markup) / PPM);
        
        // sold action proportion
        uint256 sold = action_for_sale * msg.value / player_database[pp_id].buyin_requested;
        action_owned[pp_id][msg.sender][player_database[pp_id].in_game] += sold;
        player_database[pp_id].action_sold += sold;

        if(player_database[pp_id].buyin_requested <= player_database[pp_id].curr_bankroll){
            // Forward the money to the player, and note that the player is in the game
            // Also emit event to ourselves ("this player needs funds trans")
            // player_database[pp_id].in_game = true;
            emit PlayerNeedsFunds (amountReq, play_id);
        }
        return "Invested in player";
    }
    
    //self-listening fx: once invest tx goes through, picks up that event and sends appropriate funds to player
    function backerTransPlayer(uint256 pp_id, uint256 amountReq) public payable returns(string memory fundStatus) {
        require(amountReq == player_database[pp_id].buyin_requested, "amountReq != buyin_requested");
        require(msg.sender == player_database[pp_id].pp_bank, "sender != pp_bank");
        require(player_database[pp_id].curr_bankroll >= player_database[pp_id].buyin_requested, "curr_bankroll < buyin_requested");
        //transfer investment to player
        address payable pp = payable(player_database[pp_id].pp_bank);
        pp.transfer(amountReq);
        //adjust funds available ledger
        player_database[pp_id].curr_bankroll -= amountReq;
        return "Funds sent to player";
    }
    
    // owner waiting for result (from result oracle) 
    // in this version - owner is the oracle
    // owner emits event to update result
    // player needs to listen for event on results to know to distribute profits
    // updates the results with profit and emits an event to be picked up by player, then appropriate backers
    function _updateResults(uint256 profit, uint256 pp_id, uint256 tourney_id) public returns (string memory results) {
        //require(msg.sender == owner);
        tourney_results[tourney_id][pp_id] = profit;
        emit updateResults(profit, tourney_id, pp_id);
        return "Tourney result logged";
    }
   
    // getter so player knows how much he owes after a tournament is over
    function get_amount_owed(uint256 pp_id, uint256 tourney_id) public view returns (uint256 amount){
        return (tourney_results[tourney_id][pp_id]*player_database[pp_id].action_sold) / PPM;
    }
    
    fallback () external {
        revert();
    }
}