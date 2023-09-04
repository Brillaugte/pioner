// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import "./interface/AggregatorV3Interface.sol";



contract Pioner{
    using SafeERC20 for IERC20;

    address public pioner_dao;  
    address public pythOracleaddress;

    constructor(address _pioner_dao, address _pythOracleaddress)  {
        pioner_dao = _pioner_dao;
        pythOracleaddress = _pythOracleaddress;
    }

    struct b{ //bucket
        uint256 b_id; //key

        uint256 g_im;
        uint256 cL;
    }

    struct a{ //accp
        uint256 accp_id;
    }



    struct corr{
        uint256 o_id_a;
        uint256 o_id_b;
        uint256 corr;
    }



    struct lending{
        uint256 lending_id;
    }

    // pre auction can be done with quote transfer function and a stack validation
    // buy market can be done with a limit order and a good frontend

   
    // protocol incentives
        // On liquidation, netting and settlement earn point for protocol incentives
    mapping( address => uint256 ) reward;

/* ########################################## */
/* #################  $ca $deposit ################ */
/* ########################################## */

    // collateral aggrement

    enum structType{ca,p,b,c,junior,df}

    struct ca{ 
        address token;
        structType struct_type;
        uint256 ca_r_id;
        address owner;

        uint256 qty;
        uint256 haircut;
    }

    
    mapping(uint256 => ca) ca_m;
    uint256 ca_l;

    function transfer_wallet_to_ca(uint256 _amount, uint256 ca_id) public {
        require(_amount > 0, "Deposit amount must be greater than 0");
        ca memory _ca = ca_m[ca_id];
        IERC20 token = IERC20(_ca.token);
        token.safeTransferFrom(msg.sender, address(this), _amount);
        ca_m[ca_id].qty += _amount;
    }

    // case of a new ca
    function transfer_wallet_to_ca_init(address token, structType struct_type, uint256 ca_r_id, uint256 _amount) public {
        require(_amount > 0, "Deposit amount must be greater than 0");
        IERC20 _token = IERC20(token);
        _token.safeTransferFrom(msg.sender, address(this), _amount);        
        ca memory _ca = ca(
            token,
            struct_type.ca,
            ca_r_id,
            msg.sender,
            
            _amount,
            ca_r_m[ca_r_id].haircut
        );
        ca_m[ca_l]=_ca;
        ca_l++;
        
    }

/* ########################################## */
/* #################  $withdraw  ################ */
/* ########################################## */

    // Withdraw annouced ammount. 
    function _MDRVclaimWithdraw(uint256 _amount) public {
        require(b[msg.sender] >= _amount, "Insufficient balance");
        require(withdrawMap[msg.sender].qty > _amount);
        // TODO set 1 to 5 minutes for live net.
        uint256 waitingTime = 1;
        require(withdrawMap[msg.sender].time + waitingTime < block.timestamp );
        b[msg.sender] -= _amount;
        token.safeTransfer(msg.sender, _amount);
    }

    // A hedger that wants to keeps good reputation to transfer back unsused df. 
    function _MDRV_transfer(address _to, uint256 _value) public{
        require(b[msg.sender] >= _value);
        b[msg.sender] -= _value;
        b[_to] += _value;
        emit _MDRVTransfer(msg.sender, _to, _value);
    } 

/* ########################################## */
/* #################  $c1 $swap  ################ */
/* ########################################## */

    struct c1{ //swap contract
        uint256 c_id; //key
        uint256 o_id; //key
        uint256 b_id; //key

        address a;
        address b;
        uint256 lastLiquidation;

        uint256 im;
        uint256 df_share;
        // updated to keep track in liquidation process
        uint256 last_l_id; 
    }
    mapping(uint256 => c1) c1_m;
    uint256 c1_l;

/* ########################################## */
/* #################  $c1 $option  ################ */
/* ########################################## */

        struct c2{ //option contract
        uint256 c_id; //key
        uint256 o_id; //key
        uint256 b_id; //key

        address a;
        address b;
    }

    mapping(uint256 => c2) c2_m;
    uint256 c2_l;


/* ########################################## */
/* #################  $c_transfer ################ */
/* ########################################## */

    mapping (uint256 => positionTransfer) positionTransferMap;
    uint256 positionTransferMapLenght;
    mapping (uint256 => isContractTransferable) isContractTransferableMap;

/* ########################################## */
/* #################  $withdraw ################ */
/* ########################################## */


/* ########################################## */
/* #################  $ca_r  ################ */
/* ########################################## */

    // collateral aggreement rules
    struct ca_r{ 
        address token;
        uint256 haircut;
    }
     
    mapping(uint256 => ca_r) ca_r_m;
    mapping(uint256 => address) ca_r_owner;
        // once true, owner cannot call update function
        // only add to an accp a sealed ca_r
    mapping(uint256 => bool) ca_r_sealed; 
    uint256 ca_r_l;


    function initiate_ca_r() public {
        ca_r_owner[ca_r_l] = msg.sender;
        ca_r_l++;
    }

    function deploy_ca_r(uint256 ca_r_id,address token,uint256 haircut) public {
    require(ca_r_owner[ca_r_id] == msg.sender );
    require( ca_r_sealed[ca_r_id] == false);
    ca_r memory _ca_r = ca_r(
        token,
        haircut 
        );
    ca_r_m[ca_r_id] = _ca_r;
    }

    function seal_ca_r(uint256 ca_r_id) public {
    require(ca_r_owner[ca_r_id] == msg.sender );
    ca_r_sealed[ca_r_id]  == true;
    } 

/* ########################################## */
/* #################  $portfolio ################ */
/* ########################################## */

    // EACH CA HAVE A TOTAL VALUE, POSITIONS GET CA UNITS, VALUE MUST BE 5 MIN HOLD MAX
    // THEN USER IS FREE TO SELECT COLLATERAL HE WICH TO TAKES FROM LIQUIDATED USER

    enum portfolio_type{
        portfolio, mint, lend, fund, fund_mint, fund_borrow
    }
    struct p{ //portfolio
        uint256 p_id; //key

        uint256 g_im;
        uint256 bL;
        uint256 cl;

        uint256 im_tot;
        
    }

    struct ca{ 
        address token;
        structType struct_type;
        uint256 ca_r_id;
        address owner;

        uint256 qty;
        uint256 haircut;
    }

    function transfer_ca_to_p(uint256 _amount, uint256 ca_id_ca, uint256 ca_id_p){
        ca memory _ca_ca = ca_m[ca_id];
        ca memory _ca_p = ca_m[ca_id];
        require(_amount > 0, "Deposit amount must be greater than 0");
        require(_ca_ca.qty > _amount);
        require( _ca_ca.owner == msg.sender);
        require(_ca_ca.struct_type == structType.ca);
        require(_ca_ca.token == _ca_p.token);
        
        ca_m[ca_id_ca].qty -= _amount;
        ca_m[ca_id_p].qty += _amount;
    }
    // case of a new ca
    function transfer_wallet_to_ca_init(address token, structType struct_type, uint256 ca_r_id, uint256 _amount) public {
        require(_amount > 0, "Deposit amount must be greater than 0");
               
        ca memory _ca = ca(
            token,
            struct_type.p,
            ca_r_id,
            msg.sender,
            
            _amount,
            ca_r_m[ca_r_id].haircut
        );
        ca_m[ca_l]=_ca;
        ca_l++;
        
    }

/* ########################################## */
/* #################  $open_quote ################ */
/* ########################################## */

/* ########################################## */
/* #################  $partial_fill ################ */
/* ########################################## */
    mapping(address => uint256 ) minPartialFillQty;

    // partial fill reunion is made through netting

/* ########################################## */
/* #################  $close_quote ################ */
/* ########################################## */

/* ########################################## */
/* #################  $close_quote ################ */
/* ########################################## */

    //TODO manage haircut

    function update_im_tot(){

    }

    function liquidate(){
        //if update_im_tot no holder than x
    }

    //manage remaining IM in positions

/* ########################################## */
/* #################  $partial_open ################ */
/* ########################################## */

/* ########################################## */
/* #################  $partial_close ################ */
/* ########################################## */

/* ########################################## */
/* #################  $oracle  ################ */
/* ########################################## */

    struct o{ //oracle
        bytes32 pyth_id;
        uint256 lastPrice;
        uint256 lastUpdated;
        uint256 max_delay;
        uint256 max_spread;
    }
    
    struct o_r{
        uint256 o_id;
        uint256 a_id;

        uint256 im;
        uint256 df;
        uint256 corr;
    }
    
    
    mapping( uint256 => o ) o_m;
    uint256 o_l;

    function get_price() bytes[] calldata pythUpdateData) public returns(uint256) {
        IPyth pyth = IPyth(_pM.oracle_address1);
		uint feeAmount = pyth.getUpdateFee(pythUpdateData);
		require(msg.sender.balance >= feeAmount, "Insufficient balance");
		pyth.updatePriceFeeds{value: feeAmount}(pythUpdateData);
		PythStructs.Price memory pythPrice = pyth.getPriceNoOlderThan(_pM.pyth_address1,_pM.max_delay ); //maxdelay in seconds
		require(pythPrice.price > 0, "Pyth price is zero");
		priceInt = pythPrice.price;
		time = uint256(pythPrice.publishTime);

        pM[p_id].last_price = price;
		return price;

    }
/* ########################################## */
/* #################  $netting  ################ */
/* ########################################## */

    // once a billateral in an ACCP is set, reduce it's IM.
    // big risk is when two rogue build big positions against themself to farm accp df with liquidation spread. 

    // issue is that we can reduce im by only computing biggest impact corr, but it need to be reprocessed each time one position is updated
    struct n{
        uint256 p_id;
        uint256 b_id;
        uint256 accp_id;
    }

    mapping( uint256 => n ) n_m;
    uint256 n_l;

/* ########################################## */
/* #################  $liquidation  ################ */
/* ########################################## */

    // 5 min liquidation or early if everything is reached.
    // after 4 min, updates are without oracles.
    struct l{ // liquidation
        uint256 l;
        address liquidator;
        uint256 stack;
    }

    mapping (uint256 => l) l_m;
    uint256 l_l;
    // last_update_id

    // We just know number of items, and their collateral
    // There is a function to process each one of them
    // once every items are processed, we can directly send the liquidation
    // each c have last update id, so we know wich ones havent been updated

    // function to update for collateral optimization
    function get_p_value(uint256 p_id) public {

    }

    function init_l(uint256 p_id){
        // lock stack to slash in case of wrong liquidation ?
    }

    //each position by lenght
    // tot_collateral
    // mint price
    // lending price
    // auto auction positions
    // position can be buyback
        // by counterparty to be closed ( with specific auction)
        // or buy to be close to farm df
        // same user with a proper portfolio in case of error and getting back is df
    // liquidated user gets back collateral not used in auction
        
/* ########################################## */
/* #################  $delegate $1ct  ################ */
/* ########################################## */
    
    /*
    if (delegate[msg.sender].isdelegate == false){
            _MDRVdelegate(msg.sender); 
            }
            */

    //bytes32 signed by address to check allow open x ?
    //or free but user can set limit
    mapping (address => delegateStruct) public delegate; // delegate address for 1 click trading.

    function _MDRVdelegate(address _delegate) public {
        delegate[msg.sender].delegate = _delegate;
        delegate[msg.sender].isdelegate = true;
    }
    // Account abstraction example https://github.com/thirdweb-example/unilogin
    

/* ########################################## */
/* #################  $0ct $copytrading  ################ */
/* ########################################## */

    //allow a liquidator to take the same trades as an address

/* ########################################## */
/* ################# $0ct_hedding  ################ */
/* ########################################## */
    // user give his binance keys so we pass trade for him and delegate onchain so he don't give pirvate key

/* ########################################## */
/* #################  $reputation $kyc $whitelist  ################ */
/* ########################################## */

    // position can be cancelled if it doesn't follow it own rules

    struct kyc{
        uint256 kyc_admin_id;
        bool is_blacklist;
        bool kyc_bool;
        address target;
    }

    mapping ( uint256 => kyc) kyc_m;
    uint256 kyc_l;

    mapping( uint256 => address) kyc_admin;
    uint256 kyc_admin_l;

    function initiate_kyc() public {
        kyc_admin[kyc_admin_l] = msg.sender;
        kyc_admin_l++;
    }

    function add_address_to_blacklist(uint256 kyc_admin_id, bool is_blacklist, bool kyc_bool, address target) public{
        require( kyc_admin[kyc_admin_id] == msg.sender );
        kyc memory _kyc = kyc(
            kyc_admin_id,
            is_blacklist,
            kyc_bool,
            target
            );
        kyc_m[kyc_l] = _kyc;
        kyc_l++;
    }

    function verify_kyc( uint256 kyc_admin_id, address target, uint kyc_id) public returns(bool){
        kyc memory _kyc = kyc_m[kyc_id];
        require(_kyc.target == target);
        require(_kyc.kyc_admin_id == kyc_admin_id);
        if ( _kyc.is_blacklist == true ){
            if(_kyc.kyc_bool == false ){
                return true;
            } else {
                return false;
            }
        } else { 
            if(_kyc.kyc_bool == true ){
                return true;
            } else {
                return false;
            }
        }
    }

/* ########################################## */
/* #################  $accp_df  ################ */
/* ########################################## */
    // only takes ca[0] as df collateral
    function send_df_to_accp(uint256 df, uint256 ca) private {
        // send df from ca

        // get df value

        // get share of value

    }

    function get_df_from_accp(uint256 df, uint256 ca) private{
        // compare to total personal share

        // get share portfolio * share ccp

        // add to balance
    }

      struct df{
        uint256 accp_id;
        uint256 share;
        uint256 owner;
        address token;
    }

    mapping (uint256 => df) df_m;
    uint256 df_l;
    mapping( uint256 => uint256 ) global_df_value;

    //deposit
    // only can be call from an open c
    function transfer_ca_to_df(uint256 _amount, uint256 ca_id, uint256 df_id) private {
        ca memory _ca = ca_m[ca_id];
        require(_amount > 0, "Deposit amount must be greater than 0");
        require(_ca.qty > _amount);
        uint256 share = _amount / global_df_value[df_m[df_id].accp_id];
        _ca.qty -= _amount;
        df_m[df_id].share += share;
    }

    //withdraw
    // only can be call from an open c
    function transfer_df_to_ca(uint256 share_percent, uint256 ca_id, uint256 df_id) private {
        df memory _df = df_m[df_id];
        require(share_percent > 0, "Deposit amount must be greater than 0");
        require(_df.share > 0);
        uint256 _amount = (_df.share * share_percent) / global_df_value[_df.accp_id];
        ca_m[ca_id].qty += _amount;
        df_m[df_l].share -= _df.share * share_percent;
    }
/* ########################################## */
/* #################  $junior $accp_junior  ################ */
/* ########################################## */

    struct junior{
        uint256 accp_id;
        uint256 share;
        address owner;
        address token;
    }

    mapping (uint256 => junior) junior_m;
    uint256 junior_l;
    mapping( uint256 => uint256 ) global_junior_value;

    //deposit
    function transfer_ca_to_junior(uint256 _amount, uint256 ca_id, uint256 junior_id) public {
        ca memory _ca = ca_m[ca_id];
        require(_amount > 0, "Deposit amount must be greater than 0");
        require(_ca.qty > _amount);
        require( _ca.owner == msg.sender);
        require(_ca.struct_type == structType.ca);
        uint256 share = _amount / global_junior_value[junior_m[junior_id].accp_id];
        ca_m[ca_id].qty -= _amount;
        junior_m[junior_id].share += share;
    }

    // first time deposit
    function transfer_ca_to_junior_init(uint256 ca_id, uint256 accp_id, uint256 _amount) public {
        ca memory _ca = ca_m[ca_id];
        require(_amount > 0, "Deposit amount must be greater than 0");
        require(_ca.qty > _amount);
        require(_ca.struct_type == structType.ca);
        uint256 share = _amount / global_junior_value[accp_id];
        junior memory _junior = junior(
            accp_id,
            share,
            msg.sender,
            ca_zero[accp_id] // token must be defined from ACCP rules
        );
        
        ca_m[ca_id].qty -= _amount;
        junior_m[junior_l].share += share;
        junior_l++;
    }

    //withdraw
    function transfer_junior_to_ca(uint256 share_percent, uint256 ca_id, uint256 junior_id) public {
        junior memory _junior = junior_m[junior_id];
        require(share_percent > 0, "Deposit amount must be greater than 0");
        require(_junior.share > 0);
        uint256 _amount = (_junior.share * share_percent) / global_junior_value[_junior.accp_id];
        ca_m[ca_id].qty += _amount;
        junior_m[junior_l].share -= _junior.share * share_percent;
    }

/* ########################################## */
/* #################  $fund  ################ */
/* ########################################## */

    //funds are mono currency

    struct f{
        uint256 f_id; //key

        uint256 im_tot;
    }

    struct fund{
        address owner;
        uint256 managementFee;
        uint256 performanceFee;
        uint256 totalDepositLimit;
        address token;
        bool allowDeposit;
        uint256 minDeposit;
        uint256 maxDeposit;
        
    }

    struct ca_f{
        uint256 f_id;
        uint256 share;
        uint256 owner
        
    }

    mapping ( uint256 => f ) f_m;
    uint256 f_l;

    function create_f(){}
    function transfer_ca_to_f(){}
    function transfer_f_to_ca(){}

    // withdraw time
    // fast withdraw balance ( with fees)

    // user allocation
    // settle from balance

    //deposit is taken in consideration once fund value is computed

    // if user get liquidated, auction his portfolio

    // if fund get liquidated, normal liquidation

     // TODO modifier for fund portfolio accp mint

     // TODO Use position in fund management as collateral


/* ########################################## */
/* #################  $accp_r  ################ */
/* ########################################## */

    // token addres for df and junior
    mapping( uint256 => address ) ca_zero;


/* ########################################## */
/* #################  $mint $token  ################ */
/* ########################################## */
    //TODO overide the transfer function of ACCPToken contract to allow using some DeFi protocole while still being undercollaterized

        struct mint{
        uint256 mint_id;
        address token;
        uint256 qty;
    }

    struct o_mint{
        uint256 o_mint_id;
        bytes32 price;
        uint256 lastPrice;
        uint256 lastUpdated;
        uint256 max_delay;
        uint256 max_spread;
    }

    mapping ( address => uint256 ) tokenSupply; 

    // tokenID => Token Address
    mapping(uint256 => address) public idToToken;
    // User => tokenID => Token Address
    mapping(address => mapping(uint256 => address)) public userToToken;
    uint256 public nextTokenId = 1;

    function mintForUser(address user, uint256 tokenId, uint256 amount) public {
        // freeze portfolio withdraw
        // only withdraw with oracle

        require(idToToken[tokenId] != address(0), "No token found for this ID");
        require(userToToken[user][tokenId] != address(0), "No token found for this user with this ID");

        ACCPToken token = ACCPToken(idToToken[tokenId]);
        token.mint(user, amount);
    }

    function burnFromUser(address user, uint256 tokenId, uint256 amount) public {
        require(idToToken[tokenId] != address(0), "No token found for this ID");
        require(userToToken[user][tokenId] != address(0), "No token found for this user with this ID");

        ACCPToken token = accp_token(ACCPToken[tokenId]);
        require(token.balanceOf(user) >= amount, "Insufficient balance for burn");
        token.burn(user, amount);
    }

    function transferFromUser(address sender, address recipient, uint256 tokenId, uint256 amount) public {
        require(idToToken[tokenId] != address(0), "No token found for this ID");
        require(userToToken[sender][tokenId] != address(0), "No token found for this sender with this ID");
        
        ACCPToken token = ACCPToken(idToToken[tokenId]);
        require(token.balanceOf(sender) >= amount, "Insufficient balance for transfer");

        token.transferFrom(sender, recipient, amount);
    }

    function getBalance(address user, uint256 tokenId) public view returns (uint256) {
        require(idToToken[tokenId] != address(0), "No token found for this ID");
        require(userToToken[user][tokenId] != address(0), "No token found for this user with this ID");

        ACCPToken token = ACCPToken(idToToken[tokenId]);
        return token.balanceOf(user);
    }

    function getTokenSupply(uint256 tokenId) public view returns (uint256) {
        require(idToToken[tokenId] != address(0), "No token found for this ID");

        ACCPToken token = ACCPToken(idToToken[tokenId]);
        return token.totalSupply();
    }

/* ########################################## */
/* #################  $accp_token $b_backed  ################ */
/* ########################################## */

    //accp token with transferfrom function attached who transfer also the billateral ownership
    //need modified version of uni_lp and other protocol because burning a token inside a uni-LP pool will inflict loss on every lp participants
    //allow undercollaterized stoncks token usable for defi
    
/* ########################################## */
/* #################  $lending  ################ */
/* ########################################## */

// Function to borrow a portfolio against tokens
    function borrowPortfolio(address user, uint256 tokenId, uint256 amount) public onlyParentContract {
        UserToken token = UserToken(UserToken(tokenId)); // Replace UserToken with the correct type
        require(token.balanceOf(user) >= amount, "Insufficient balance for borrowing");

        // Transfer tokens as collateral to this contract
        token.transferFrom(user, address(this), amount);
        borrowedTokens[user] = amount;
    }

    // Function to return borrowed tokens and get back the portfolio
    function returnBorrowedPortfolio(address user, uint256 tokenId) public onlyParentContract {
        UserToken token = UserToken(UserToken(tokenId)); // Replace UserToken with the correct type
        require(borrowedTokens[user] > 0, "No borrowed tokens found");

        // Transfer back the tokens to the user
        token.transfer(user, borrowedTokens[user]);
        borrowedTokens[user] = 0;
    }

    // TODO variable borrowing rate

/* ########################################## */
/* #################  $paraswap $token_swap  ################ */
/* ########################################## */
    // min ammount to receive based on price oracle ( to not triger a liquidation )
    // https://github.com/aave/protocol-v2/blob/master/contracts/adapters/BaseParaSwapSellAdapter.sol

/* ########################################## */
/* #################  $zero_liquidation  ################ */
/* ########################################## */

    // This mode allow once activated by a user to allow anyone to buy a position if collateral of a position is bellow a threshold
    // Avoiding paying default fee

    mapping(address => uint256) noLiquidationThreshold;
    mapping(address => uint256) noLiquidationReward;
    // set at wich ratio collateral left / im_A to allow someone buy the position
    function setNoLiquidationMode(uint256 threshold, uint256 reward) public {
        address s = msg.sender;
        noLiquidationThreshold[s] = threshold;
        require(reward < 1 );
        noLiquidationReward[s] = reward;
    }

    // Hedger
    // Call getPrice to update price before calling that function.
    function noLiquidationCall(uint256 c_id, address target) public {
        address s = msg.sender;
        c memory _c = cM[c_id];
        p memory _p = pM[_c.oracle];
        require( _c.state == _State.Open);
        require(block.timestamp - _p.timestamp < _p.max_delay, "Update price feed " );

        
        uint256 im_A = _p.im_A;
        uint256 im_B = _p.im_B;
        address p_A = _c.p_A;
        address p_B = _c.p_B;
        uint256 _noLiquidationThreshold_A = noLiquidationThreshold[p_A];
        uint256 _noLiquidationThreshold_B = noLiquidationThreshold[p_B];
        uint256 price = _p.last_price;
        (uint256 uPnL_A,uint256 uPnL_B) = _MDRVuPnL(c_id, price);

        if ( target == p_A ) { 
            require(_noLiquidationThreshold_A > (  uPnL_A * _c.qty ) / im_A, "too early");
            uint256 updateAmount = ( im_A * _noLiquidationThreshold_A ) * ( 1 - noLiquidationReward[p_A] ) + _p.df_A ;
            require(b[s] > updateAmount);
            b[s] -= updateAmount;
            b[p_A] += updateAmount;
            _c.p_A == s;
        }
        if ( target == p_A ) { 
            require(_noLiquidationThreshold_B > (  uPnL_B * _c.qty ) / im_B, "too early");
            uint256 updateAmount = ( im_B * _noLiquidationThreshold_B ) + _p.df_B;
            require(b[s] > updateAmount);
            b[s] -= updateAmount;
            b[p_B] += updateAmount;
            _c.p_B == s;
        }
    }

/* ########################################## */
/* #################  $affiliation  ################ */
/* ########################################## */

    // fixed affiliation fee for accp ?

    mapping(address => uint256 ) affiliateFee;

    struct updateAffiliateFee{
        uint256 time;
        uint256 newFee;
    }
    mapping(address => updateAffiliateFee) updateAffiliateFeeMap;

    // Goal is to avoid suddent affiliate fee update
    function setaffiliateFee(uint256 newFee) public {
        address s = msg.sender ;
        updateAffiliateFee memory _updateAffiliateFee = updateAffiliateFeeMap[s];
        if ( _updateAffiliateFee.time == 0 ){ // initialisation
            updateAffiliateFeeMap[s].time = block.timestamp;
            affiliateFee[msg.sender] == newFee;
        } else {
            require(_updateAffiliateFee.time > 1 weeks);
            updateAffiliateFeeMap[s].time = block.timestamp;
            affiliateFee[msg.sender] == _updateAffiliateFee.newFee;
        }
    }

    function getAffiliateFee(address target) public view returns (address){
        return(affiliateFee[target]);
    }

    function getUpdateAffiliateFeeStruct(address target) public view returns (uint256, uint256){
        return(updateAffiliateFeeMap[target].time, updateAffiliateFeeMap[target].newFee);
    }


/* ########################################## */
/* #################  $accp_vote  ################ */
/* ########################################## */

    //based on junior or df since it is the only global variable with collateral
    // mapping ( uint256 => modify_proposition_accp_r ) modify_proposition_accp_r_m;
    // function modify_proposition_accp_r(){}

}


contract ACCPToken is ERC20 {
    address public parentContract;

    constructor(address _parentContract, string memory name, string memory symbol) ERC20(name, symbol) {
        parentContract = _parentContract;
    }

    modifier onlyParentContract() {
        require(msg.sender == parentContract, "Only parent contract can perform this action");
        _;
    }

    function mint(address to, uint256 amount) external onlyParentContract {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyParentContract {
        _burn(from, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
    if (msg.sender == parentContract) {
        // Bypass allowance check if called by ParentContract
        _transfer(sender, recipient, amount);
        return true;
    } else {
        return super.transferFrom(sender, recipient, amount);
        }
    }


}

