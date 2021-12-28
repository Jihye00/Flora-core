// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

interface IFloraLottery {
    /**
     * @notice Buy tickets for the current lottery
     * @param _lotteryId: lotteryId
     * @param _ticketNumbers: array of ticket numbers between 1,000,000 and 1,999,999
     * @dev Callable by users
     */
    function buyTickets(uint256 _lotteryId, uint32[] calldata _ticketNumbers) external;

    /**
     * @notice Claim a set of winning tickets for a lottery
     * @param _lotteryId: lottery id
     * @param _ticketIds: array of ticket ids
     * @param _brackets: array of brackets for the ticket ids
     * @dev Callable by users only, not contract!
     */
    function claimTickets(
        uint256 _lotteryId,
        uint256[] calldata _ticketIds,
        uint32[] calldata _brackets
    ) external;

    /**
     * @notice Close lottery
     * @param _lotteryId: lottery id
     * @dev Callable by operator
     */
    function closeLottery(uint256 _lotteryId) external;

    /**
     * @notice Draw the final number, calculate reward in PRoA per group, and make lottery claimable
     * @param _lotteryId: lottery id
     * @param _autoInjection: reinjects funds into next lottery (vs. withdrawing all)
     * @dev Callable by operator
     */
    function drawFinalNumberAndMakeLotteryClaimable(uint256 _lotteryId, bool _autoInjection) external;

    /**
     * @notice Inject funds
     * @param _lotteryId: lottery id
     * @param _amount: amount to inject in PRoA token
     * @dev Callable by operator
     */
    function injectFunds(uint256 _lotteryId, uint256 _amount) external;

    /**
     * @notice Start the lottery
     * @dev Callable by operator
     * @param _endTime: endTime of the lottery
     * @param _priceTicketInPRoA: price of a ticket in PRoA
     * @param _discountDivisor: the divisor to calculate the discount magnitude for bulks
     * @param _rewardsBreakdown: breakdown of rewards per bracket (must sum to 10,000)
     * @param _bankFee: bank fee (10,000 = 100%, 100 = 1%)
     */
    function startLottery(
        uint256 _endTime,
        uint256 _priceTicketInPRoA,
        uint256 _discountDivisor,
        uint256[5] calldata _rewardsBreakdown,
        uint256 _bankFee
    ) external;

    /**
     * @notice View current lottery id
     */
    function viewCurrentLotteryId() external view returns (uint256);
}
