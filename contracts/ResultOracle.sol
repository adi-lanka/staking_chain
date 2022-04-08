// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.7.0;
// Oracle that has results of games so profits can be distributed
contract ResultOracle {
    address public owner;
    
    constructor (address _owner) {
        owner = _owner;
    }
    
    event ResultUpdate (uint profit, uint256 pp_id, uint256 tourney_id);
    // emit event with results, player_id, tourney_id
    function updateResults (uint profit, uint256 pp_id, uint256 tourney_id) public {
        require (msg.sender == owner);
        emit ResultUpdate (profit, pp_id, tourney_id);
    }
}