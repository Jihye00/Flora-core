// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./utils/Address.sol";
import "./utils/Ownable.sol";
import "./utils/Context.sol";
import "./interfaces/IERC20.sol";
import "./utils/ReentrancyGuard.sol";
import "./interfaces/IFloraLottery.sol";
import "./utils/SafeMath.sol";
import "./utils/Address.sol";
import "./utils/ERC20.sol";
import "./utils/SafeERC20.sol";
import "./interfaces/IASSET.sol";
// import "./utils/oraclizeAPI_0.5.sol";


/** @title Flora Lottery.
 * @notice It is a contract for a lottery system using
 * randomness provided externally.
 */
abstract contract FloraLottery is ReentrancyGuard, ERC20, IFloraLottery, Ownable{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Address for address;

    uint public randomNumber;

    address public injectorAddress;
    address public operatorAddress;
    address public bankAddress;

    uint256 public currentLotteryId;
    uint256 public currentTicketId;

    uint256 public maxNumberTicketsPerBuyOrClaim = 100;

    uint256 public maxPriceTicketInAcacia = 50 ether;
    uint256 public minPriceTicketInAcacia = 0.005 ether;

    uint256 public pendingInjectionNextLottery;

    uint256 public constant MIN_DISCOUNT_DIVISOR = 300;
    uint256 public constant MIN_LENGTH_LOTTERY = 6 hours - 5 minutes; // 6 hours
    uint256 public constant MAX_LENGTH_LOTTERY = 4 days + 5 minutes; // 4 days
    uint256 public constant MAX_BANK_FEE = 3500; // 35%

    IERC20 public acaToken;
    address public aca;

    enum Status {
        Pending,
        Open,
        Close,
        Claimable
    }

    struct Lottery {
        Status status;
        uint256 startTime;
        uint256 endTime;
        uint256 priceTicketInAcacia;
        uint256 discountDivisor;
        uint256[5] rewardsBreakdown; // 0: 1 matching number // 4: 5 matching numbers, [4000, 2000, 1000, 600, 400]
        uint256 bankFee; // 500: 5% // 200: 2% // 50: 0.5%
        uint256[5] acaPerBracket; 
        uint256[5] countWinnersPerBracket;
        uint256 firstTicketId;
        uint256 firstTicketIdNextLottery;
        uint256 amountCollectedInAcacia;
        uint32 finalNumber;
    }

    struct Ticket {
        uint32 number;
        address owner;
    }
    
    // Mapping are cheaper than arrays
    mapping(uint256 => Lottery) private _lotteries;
    mapping(uint256 => Ticket) private _tickets;

    // Bracket calculator is used for verifying claims for ticket prizes
    mapping(uint32 => uint32) private _bracketCalculator;

    // Keeps track of number of ticket per unique combination for each lotteryId
    mapping(uint256 => mapping(uint32 => uint256)) private _numberTicketsPerLotteryId;

    // Keep track of user ticket ids for a given lotteryId
    mapping(address => mapping(uint256 => uint256[])) private _userTicketIdsPerLotteryId;

    modifier notContract() {
        require(!_isContract(msg.sender), "Contract not allowed");
        require(msg.sender == tx.origin, "Proxy contract not allowed");
        _;
    }

    modifier onlyOperator() {
        require(msg.sender == operatorAddress, "Not operator");
        _;
    }

    modifier onlyOwnerOrInjector() {
        require((msg.sender == owner()) || (msg.sender == injectorAddress), "Not owner or injector");
        _;
    }

    event AdminTokenRecovery(address token, uint256 amount);
    event LotteryClose(uint256 indexed lotteryId, uint256 firstTicketIdNextLottery);
    event LotteryInjection(uint256 indexed lotteryId, uint256 injectedAmount);
    event LotteryOpen(
        uint256 indexed lotteryId,
        uint256 startTime,
        uint256 endTime,
        uint256 priceTicketInAcacia,
        uint256 firstTicketId,
        uint256 injectedAmount
    );
    event LotteryNumberDrawn(uint256 indexed lotteryId, uint256 finalNumber, uint256 countWinningTickets);
    event NewOperatorAndBankAndInjectorAddresses(address operator, address bank, address injector);
    event TicketsPurchase(address indexed buyer, uint256 indexed lotteryId, uint256 numberTickets);
    event TicketsClaim(address indexed claimer, uint256 amount, uint256 indexed lotteryId, uint256 numberTickets);

    /**
     * @notice Constructor
     * @param _acaTokenAddress: address of the Acacia token
     */
    constructor(address _acaTokenAddress) public {
        //oraclize_setProof(proofType_Ledger);
        acaToken = IERC20(_acaTokenAddress);
        aca = _acaTokenAddress;
        // Initializes a mapping
        _bracketCalculator[0] = 11; //5th place
        _bracketCalculator[1] = 111;
        _bracketCalculator[2] = 1111;
        _bracketCalculator[3] = 11111;
        _bracketCalculator[4] = 111111; //1st place
        //_bracketCalculator[5] = 111111;
    }

    /**
     * @notice Buy tickets for the current lottery
     * @param _lotteryId: lotteryId
     * @param _ticketNumbers: array of ticket numbers between 100,000 and 177,777
     * @dev Callable by users
     */
    function buyTickets(uint256 _lotteryId, uint32[] calldata _ticketNumbers)
        virtual
        override
        external
        notContract
        nonReentrant
    {
        require(_ticketNumbers.length != 0, "No ticket specified");
        require(_ticketNumbers.length <= maxNumberTicketsPerBuyOrClaim, "Too many tickets");

        require(_lotteries[_lotteryId].status == Status.Open, "Lottery is not open");
        require(block.timestamp < _lotteries[_lotteryId].endTime, "Lottery is over");

        // Calculate number of Acacia to this contract
        uint256 amountAcaciaToTransfer = _calculateTotalPriceForBulkTickets(
            _lotteries[_lotteryId].discountDivisor,
            _lotteries[_lotteryId].priceTicketInAcacia,
            _ticketNumbers.length
        );

        // Transfer Acacia tokens to this contract
        acaToken.safeTransferFrom(address(msg.sender), address(this), amountAcaciaToTransfer);

        // Increment the total amount collected for the lottery round
        _lotteries[_lotteryId].amountCollectedInAcacia += amountAcaciaToTransfer;

        for (uint256 i = 0; i < _ticketNumbers.length; i++) {
            uint32 thisTicketNumber = _ticketNumbers[i];
            thisTicketNumber = thisTicketNumber;
            require((thisTicketNumber >= 100000) && (thisTicketNumber <= 177777), "Outside range");

            _numberTicketsPerLotteryId[_lotteryId][111111 + uint32(thisTicketNumber / 1)]++; //1st place
            _numberTicketsPerLotteryId[_lotteryId][11111 + uint32(thisTicketNumber / 10)]++;
            _numberTicketsPerLotteryId[_lotteryId][1111 + uint32(thisTicketNumber / 100)]++;
            _numberTicketsPerLotteryId[_lotteryId][111 + uint32(thisTicketNumber / 1000)]++;
            _numberTicketsPerLotteryId[_lotteryId][11 + uint32(thisTicketNumber / 10000)]++; //5th place
            //_numberTicketsPerLotteryId[_lotteryId][111111 + (thisTicketNumber % 1000000)]++;

            _userTicketIdsPerLotteryId[msg.sender][_lotteryId].push(currentTicketId);

            _tickets[currentTicketId] = Ticket({number: thisTicketNumber - 100000, owner: msg.sender});

            // Increase lottery ticket number
            currentTicketId++;
        }

        emit TicketsPurchase(msg.sender, _lotteryId, _ticketNumbers.length);
    }

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
    ) external virtual override notContract nonReentrant {
        require(_ticketIds.length == _brackets.length, "Not same length");
        require(_ticketIds.length != 0, "Length must be >0");
        require(_ticketIds.length <= maxNumberTicketsPerBuyOrClaim, "Too many tickets");
        require(_lotteries[_lotteryId].status == Status.Claimable, "Lottery not claimable");

        // Initializes the rewardInAcaciaToTransfer
        uint256 rewardInAcaciaToTransfer;

        for (uint256 i = 0; i < _ticketIds.length; i++) {
            require(_brackets[i] < 5, "Bracket out of range"); // Must be between 0 and 4

            uint256 thisTicketId = _ticketIds[i];

            require(_lotteries[_lotteryId].firstTicketIdNextLottery > thisTicketId, "TicketId too high");
            require(_lotteries[_lotteryId].firstTicketId <= thisTicketId, "TicketId too low");
            require(msg.sender == _tickets[thisTicketId].owner, "Not the owner");

            // Update the lottery ticket owner to 0x address
            _tickets[thisTicketId].owner = address(0);

            uint256 rewardForTicketId = _calculateRewardsForTicketId(_lotteryId, thisTicketId, _brackets[i]);

            // Check user is claiming the correct bracket
            require(rewardForTicketId != 0, "No prize for this bracket");

            if (_brackets[i] != 4) {
                require(
                    _calculateRewardsForTicketId(_lotteryId, thisTicketId, _brackets[i] + 1) == 0,
                    "Bracket must be higher"
                );
            }

            // Increment the reward to transfer
            rewardInAcaciaToTransfer += rewardForTicketId;
        }

        // Transfer money to msg.sender
        acaToken.safeTransfer(msg.sender, rewardInAcaciaToTransfer);

        emit TicketsClaim(msg.sender, rewardInAcaciaToTransfer, _lotteryId, _ticketIds.length);
    }

    /**
     * @notice Close lottery
     * @param _lotteryId: lottery id
     * @dev Callable by operator
     */
    function closeLottery(uint256 _lotteryId) external virtual override onlyOperator nonReentrant {
        require(_lotteries[_lotteryId].status == Status.Open, "Lottery not open");
        require(block.timestamp > _lotteries[_lotteryId].endTime, "Lottery not over");
        _lotteries[_lotteryId].firstTicketIdNextLottery = currentTicketId;

        _lotteries[_lotteryId].status = Status.Close;

        emit LotteryClose(_lotteryId, currentTicketId);
    }

    /**
     * @notice Draw the final number, calculate reward in Acacia per group, and make lottery claimable
     * @param _lotteryId: lottery id
     * @dev Callable by operator
     */
    function drawFinalNumberAndMakeLotteryClaimable(uint256 _lotteryId, uint32 _randomNumber)
        virtual
        external
        onlyOperator
        nonReentrant
    {
        require(_lotteries[_lotteryId].status == Status.Close, "Lottery not close");

        // Calculate the finalNumber based on the randomResult generated by ChainLink's fallback
        uint32 finalNumber = _randomNumber;

        // Initialize a number to count addresses in the previous bracket
        uint256 numberAddressesInPreviousBracket = 0;
        uint256 amountToBank = 0;
        // Calculate the amount to share post-bank fee
        uint256 amountToShareToWinners = (
            ((_lotteries[_lotteryId].amountCollectedInAcacia) * (10000 - _lotteries[_lotteryId].bankFee))
        ) / 10000;

        // Initializes the amount to withdraw to bank
        uint256 amountToWithdrawToBank;

        // Calculate prizes in Acacia for each bracket by starting from the highest one
        for (uint32 i = 0; i < 5; i++) {
            uint32 j = 4 - i;
            uint32 transformedWinningNumber = _bracketCalculator[j] + uint32(finalNumber / (uint32(10)**(i)));

            _lotteries[_lotteryId].countWinnersPerBracket[j] =
                _numberTicketsPerLotteryId[_lotteryId][transformedWinningNumber] -
                numberAddressesInPreviousBracket;

            // A. If number of users for this _bracket number is superior to 0
            if (
                (_numberTicketsPerLotteryId[_lotteryId][transformedWinningNumber] - numberAddressesInPreviousBracket) !=
                0
            ) {
                // B. If rewards at this bracket are > 0, calculate, else, report the numberAddresses from previous bracket
                if (_lotteries[_lotteryId].rewardsBreakdown[j] != 0) {
                    _lotteries[_lotteryId].acaPerBracket[j] =
                        ((_lotteries[_lotteryId].rewardsBreakdown[j].mul(amountToShareToWinners)).div(
                            (_numberTicketsPerLotteryId[_lotteryId][transformedWinningNumber] -
                                numberAddressesInPreviousBracket))).div(
                        10000);

                    // Update numberAddressesInPreviousBracket
                    numberAddressesInPreviousBracket = _numberTicketsPerLotteryId[_lotteryId][transformedWinningNumber];
                }
                // A. No Acacia to distribute, they are added to the amount to withdraw to bank address
            } else {
                _lotteries[_lotteryId].acaPerBracket[j] = 0;

                amountToWithdrawToBank +=
                    (_lotteries[_lotteryId].rewardsBreakdown[j] * amountToShareToWinners) /
                    10000;
            }
        }

        // Update internal statuses for lottery
        _lotteries[_lotteryId].finalNumber = finalNumber;
        _lotteries[_lotteryId].status = Status.Claimable;

        pendingInjectionNextLottery = amountToWithdrawToBank.mul(3500).div(10000);
        IAsset(aca).burn(amountToWithdrawToBank.mul(6500).div(10000)); // We will burn amountToWithdrawToBank.

        amountToBank = amountToBank.add((_lotteries[_lotteryId].amountCollectedInAcacia - amountToShareToWinners)); //Add bank fee

        // Transfer Acacia to bank address
        if (amountToBank != 0) {
            acaToken.safeTransfer(bankAddress, amountToBank);
        }
        emit LotteryNumberDrawn(currentLotteryId, finalNumber, numberAddressesInPreviousBracket);
    }

    /**
     * @notice Inject funds
     * @param _lotteryId: lottery id
     * @param _amount: amount to inject in Acacia token
     * @dev Callable by owner or injector address
     */
    function injectFunds(uint256 _lotteryId, uint256 _amount) external virtual override onlyOwnerOrInjector {
        require(_lotteries[_lotteryId].status == Status.Open, "Lottery not open");

        acaToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        _lotteries[_lotteryId].amountCollectedInAcacia += _amount;

        emit LotteryInjection(_lotteryId, _amount);
    }

    /**
     * @notice Start the lottery
     * @dev Callable by operator
     * @param _endTime: endTime of the lottery
     * @param _priceTicketInAcacia: price of a ticket in Acacia
     * @param _discountDivisor: the divisor to calculate the discount magnitude for bulks
     * @param _rewardsBreakdown: breakdown of rewards per bracket (must sum to 10,000)
     * @param _bankFee: bank fee (10,000 = 100%, 100 = 1%)
     */
    function startLottery(
        uint256 _endTime,
        uint256 _priceTicketInAcacia,
        uint256 _discountDivisor,
        uint256[5] calldata _rewardsBreakdown,
        uint256 _bankFee
    ) external virtual override onlyOperator {
        require(
            (currentLotteryId == 0) || (_lotteries[currentLotteryId].status == Status.Claimable),
            "Not time to start lottery"
        );

        require(
            ((_endTime - block.timestamp) > MIN_LENGTH_LOTTERY) && ((_endTime - block.timestamp) < MAX_LENGTH_LOTTERY),
            "Lottery length outside of range"
        );

        require(
            (_priceTicketInAcacia >= minPriceTicketInAcacia) && (_priceTicketInAcacia <= maxPriceTicketInAcacia),
            "Outside of limits"
        );

        require(_discountDivisor >= MIN_DISCOUNT_DIVISOR, "Discount divisor too low");
        require(_bankFee <= MAX_BANK_FEE, "Bank fee too high");

        require(
            (_rewardsBreakdown[0] +
                _rewardsBreakdown[1] +
                _rewardsBreakdown[2] +
                _rewardsBreakdown[3] +
                _rewardsBreakdown[4]) == 9000,
                //_rewardsBreakdown[5]) == 10000,
            "Rewards must equal 9000"
        );

        currentLotteryId++;

        _lotteries[currentLotteryId] = Lottery({
            status: Status.Open,
            startTime: block.timestamp,
            endTime: _endTime,
            priceTicketInAcacia: _priceTicketInAcacia,
            discountDivisor: _discountDivisor,
            rewardsBreakdown: _rewardsBreakdown,
            bankFee: _bankFee,
            acaPerBracket: [uint256(0), uint256(0), uint256(0), uint256(0), uint256(0)], //Original : 6
            countWinnersPerBracket: [uint256(0), uint256(0), uint256(0), uint256(0), uint256(0)], //Original : 6
            firstTicketId: currentTicketId,
            firstTicketIdNextLottery: currentTicketId,
            amountCollectedInAcacia: pendingInjectionNextLottery,
            finalNumber: 0
        });

        emit LotteryOpen(
            currentLotteryId,
            block.timestamp,
            _endTime,
            _priceTicketInAcacia,
            currentTicketId,
            pendingInjectionNextLottery
        );

        pendingInjectionNextLottery = 0;
    }

    /**
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @param _tokenAddress: the address of the token to withdraw
     * @param _tokenAmount: the number of token amount to withdraw
     * @dev Only callable by owner.
     */
    function recoverWrongTokens(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
        require(_tokenAddress != address(acaToken), "Cannot be Acacia token");

        IERC20(_tokenAddress).safeTransfer(address(msg.sender), _tokenAmount);

        emit AdminTokenRecovery(_tokenAddress, _tokenAmount);
    }

    /**
     * @notice Set Acacia price ticket upper/lower limit
     * @dev Only callable by owner
     * @param _minPriceTicketInAcacia: minimum price of a ticket in Acacia
     * @param _maxPriceTicketInAcacia: maximum price of a ticket in Acacia
     */
    function setMinAndMaxTicketPriceInAcacia(uint256 _minPriceTicketInAcacia, uint256 _maxPriceTicketInAcacia)
        external
        onlyOwner
    {
        require(_minPriceTicketInAcacia <= _maxPriceTicketInAcacia, "minPrice must be < maxPrice");
        
        minPriceTicketInAcacia = _minPriceTicketInAcacia;
        maxPriceTicketInAcacia = _maxPriceTicketInAcacia;
    }

    /**
     * @notice Set max number of tickets
     * @dev Only callable by owner
     */
    function setMaxNumberTicketsPerBuy(uint256 _maxNumberTicketsPerBuy) external onlyOwner {
        require(_maxNumberTicketsPerBuy != 0, "Must be > 0");
        maxNumberTicketsPerBuyOrClaim = _maxNumberTicketsPerBuy;
    }

    /**
     * @notice Set operator, bank, and injector addresses
     * @dev Only callable by owner
     * @param _operatorAddress: address of the operator
     * @param _bankAddress: address of the bank
     * @param _injectorAddress: address of the injector
     */
    function setOperatorAndBankAndInjectorAddresses(
        address _operatorAddress,
        address _bankAddress,
        address _injectorAddress
    ) external onlyOwner {
        require(_operatorAddress != address(0), "Cannot be zero address");
        require(_bankAddress != address(0), "Cannot be zero address");
        require(_injectorAddress != address(0), "Cannot be zero address");

        operatorAddress = _operatorAddress;
        bankAddress = _bankAddress;
        injectorAddress = _injectorAddress;

        emit NewOperatorAndBankAndInjectorAddresses(_operatorAddress, _bankAddress, _injectorAddress);
    }

    /**
     * @notice Calculate price of a set of tickets
     * @param _discountDivisor: divisor for the discount
     * @param _priceTicket price of a ticket (in Acacia)
     * @param _numberTickets number of tickets to buy
     */
    function calculateTotalPriceForBulkTickets(
        uint256 _discountDivisor,
        uint256 _priceTicket,
        uint256 _numberTickets
    ) external pure returns (uint256) {
        require(_discountDivisor >= MIN_DISCOUNT_DIVISOR, "Must be >= MIN_DISCOUNT_DIVISOR");
        require(_numberTickets != 0, "Number of tickets must be > 0");

        return _calculateTotalPriceForBulkTickets(_discountDivisor, _priceTicket, _numberTickets);
    }

    /**
     * @notice View current lottery id
     */
    function viewCurrentLotteryId() external view virtual override returns (uint256) {
        return currentLotteryId;
    }

    /**
     * @notice View lottery information
     * @param _lotteryId: lottery id
     */
    function viewLottery(uint256 _lotteryId) external view returns (Lottery memory) {
        return _lotteries[_lotteryId];
    }

    /**
     * @notice View ticker statuses and numbers for an array of ticket ids
     * @param _ticketIds: array of _ticketId
     */
    function viewNumbersAndStatusesForTicketIds(uint256[] calldata _ticketIds)
        external
        view
        returns (uint32[] memory, bool[] memory)
    {
        uint256 length = _ticketIds.length;
        uint32[] memory ticketNumbers = new uint32[](length);
        bool[] memory ticketStatuses = new bool[](length);

        for (uint256 i = 0; i < length; i++) {
            ticketNumbers[i] = _tickets[_ticketIds[i]].number;
            if (_tickets[_ticketIds[i]].owner == address(0)) {
                ticketStatuses[i] = true;
            } else {
                ticketStatuses[i] = false;
            }
        }

        return (ticketNumbers, ticketStatuses);
    }

    /**
     * @notice View rewards for a given ticket, providing a bracket, and lottery id
     * @dev Computations are mostly offchain. This is used to verify a ticket!
     * @param _lotteryId: lottery id
     * @param _ticketId: ticket id
     * @param _bracket: bracket for the ticketId to verify the claim and calculate rewards
     */
    function viewRewardsForTicketId(
        uint256 _lotteryId,
        uint256 _ticketId,
        uint32 _bracket
    ) external view returns (uint256) {
        // Check lottery is in claimable status
        if (_lotteries[_lotteryId].status != Status.Claimable) {
            return 0;
        }

        // Check ticketId is within range
        if (
            (_lotteries[_lotteryId].firstTicketIdNextLottery < _ticketId) &&
            (_lotteries[_lotteryId].firstTicketId >= _ticketId)
        ) {
            return 0;
        }

        return _calculateRewardsForTicketId(_lotteryId, _ticketId, _bracket);
    }

    /**
     * @notice View user ticket ids, numbers, and statuses of user for a given lottery
     * @param _user: user address
     * @param _lotteryId: lottery id
     * @param _cursor: cursor to start where to retrieve the tickets
     * @param _size: the number of tickets to retrieve
     */
    function viewUserInfoForLotteryId(
        address _user,
        uint256 _lotteryId,
        uint256 _cursor,
        uint256 _size
    )
        external
        view
        returns (
            uint256[] memory,
            uint32[] memory,
            bool[] memory,
            uint256
        )
    {
        uint256 length = _size;
        uint256 numberTicketsBoughtAtLotteryId = _userTicketIdsPerLotteryId[_user][_lotteryId].length;

        if (length > (numberTicketsBoughtAtLotteryId - _cursor)) {
            length = numberTicketsBoughtAtLotteryId - _cursor;
        }

        uint256[] memory lotteryTicketIds = new uint256[](length); //Original : all 3 dynamic array is declared with new keyword
        uint32[] memory ticketNumbers = new uint32[](length);
        bool[] memory ticketStatuses = new bool[](length);

        for (uint256 i = 0; i < length; i++) {
            lotteryTicketIds[i] = _userTicketIdsPerLotteryId[_user][_lotteryId][i + _cursor];
            ticketNumbers[i] = _tickets[lotteryTicketIds[i]].number;

            // True = ticket claimed
            if (_tickets[lotteryTicketIds[i]].owner == address(0)) {
                ticketStatuses[i] = true;
            } else {
                // ticket not claimed (includes the ones that cannot be claimed)
                ticketStatuses[i] = false;
            }
        }

        return (lotteryTicketIds, ticketNumbers, ticketStatuses, _cursor + length);
    }

    /**
     * @notice Calculate rewards for a given ticket
     * @param _lotteryId: lottery id
     * @param _ticketId: ticket id
     * @param _bracket: bracket for the ticketId to verify the claim and calculate rewards
     */
    function _calculateRewardsForTicketId(
        uint256 _lotteryId,
        uint256 _ticketId,
        uint32 _bracket
    ) internal view returns (uint256) {
        // Retrieve the winning number combination
        uint32 winningTicketNumber = _lotteries[_lotteryId].finalNumber;

        // Retrieve the user number combination from the ticketId
        uint32 userNumber = _tickets[_ticketId].number;

        // Apply transformation to verify the claim provided by the user is true
        uint32 transformedWinningNumber = _bracketCalculator[_bracket] + uint32(winningTicketNumber / (uint32(10)**(4 - _bracket)));

        uint32 transformedUserNumber = _bracketCalculator[_bracket] + uint32(userNumber / (uint32(10)**(4 - _bracket)));

        // Confirm that the two transformed numbers are the same, if not throw
        if (transformedWinningNumber == transformedUserNumber) {
            return _lotteries[_lotteryId].acaPerBracket[_bracket];
        } else {
            return 0;
        }
    }

    /**
     * @notice Calculate final price for bulk of tickets
     * @param _discountDivisor: divisor for the discount (the smaller it is, the greater the discount is)
     * @param _priceTicket: price of a ticket
     * @param _numberTickets: number of tickets purchased
     */
    function _calculateTotalPriceForBulkTickets(
        uint256 _discountDivisor,
        uint256 _priceTicket,
        uint256 _numberTickets
    ) internal pure returns (uint256) {
        return (_priceTicket * _numberTickets * (_discountDivisor + 1 - _numberTickets)) / _discountDivisor;
    }
    
    // function _callback(bytes32 queryId, string result, bytes proof) public onlyOperator{
    //     require (msg.sender == oraclize_cbAddress());

    //     if (oraclize_randomDS_proofVerify__returnCode(queryId, result, proof) == 0) {
    //         uint maxRange = 2 ** (8 * 7);
    //         randomNumber = uint(keccak256(abi.encodePacked(result)) % maxRange;
    //     } else {
    //         // Proof fails
    //     }
    // }

    // function getRandomNumber() public payable onlyOperator{
    //     uint numberOfBytes = 7;
    //     uint delay = 0;
    //     uint callbackGas = 200000;

    //     bytes32 queryId = oraclize_newRandomDSQuery(delay, numberOfBytes, callbackGas);
    // }

    /**
     * @notice Check if an address is a contract
     */
    function _isContract(address _addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(_addr)
        }
        return size > 0;
    }
}