//+-------------------------------------------------------------------+
//|                                       Holy Graily Candle Bob.mq4  |
//|                                    Copyright 2012, Steve Hopwood  |
//|                              http://www.hopwood3.freeserve.co.uk  |
//+-------------------------------------------------------------------+

#define  version "Version 1k"

#property copyright "Copyright 2012, Steve Hopwood"
#property link      "http://www.hopwood3.freeserve.co.uk"
#include <WinUser32.mqh>
#include <stdlib.mqh>
#define  NL    "\n"
#define  up " :Up"
#define  down " :Down"
#define  mixed "Mixed"
#define  nomovement " :No movement"
#define  ranging "Ranging"
#define  both "Both"
#define  buy "Buy"
#define  sell "Sell"

//SuperSlope colours
#define  red "Red"
#define  blue "Blue"
//Changed by tomele
#define white "White"

///Using hgi_lib
//The HGI library functionality was added by tomele. Many thanks Thomas.
#import "hgi_lib.ex4"
   enum SIGNAL {NOSIGNALNE=0,TRENDUP=1,TRENDDN=2,RANGEUP=3,RANGEDN=4,RADUP=5,RADDN=6};
   enum SLOPE {UNDEFINED=0,RANGEABOVE=1,RANGEBELOW=2,TRENDABOVE=3,TRENDBELOW=4};
   SIGNAL getHGISignal(string symbol,int timeframe,int shift);
   SLOPE getHGISlope (string symbol,int timeframe,int shift);
#import

/*
TDesk is a brilliant project being developed by tomele at http://www.stevehopwoodforex.com/phpBB3/viewtopic.php?p=163522#p163522
Thomas also provided the code to make EA's compatible with TDesk. Find the code by searching for "TDesk code"."
These are outstanding contribution to SHF by a fantastic individual. Thank you Thomas, from all of us.
*/
// TDesk code
#include <TDesk.mqh>

/*
SHF member Ehrenmat (Mat) sent me a version of HGCB with slipshod's (Andrew) support and resistance indicator
implemented for take profit and stop loss points, along with the option not to take trades from
within S/R zones. You will find David's indi at http://www.stevehopwoodforex.com/phpBB3/viewtopic.php?f=27&t=514.
Fabulous work, Mat. Thanks.
Do a search for "UseSuppRes" to find the relevant code.
*/
#include <LibSSSRv5.mqh>

//HGI constants
#define  hginoarrow " No relevant signal"
#define  hgiuparrowtradable " Tradable up arrow"
#define  hgidownarrowtradable " Tradable down arrow"
#define  hgiuparrowuntradable " Untradable up arrow"
#define  hgidownarrowuntradable " Untradable down arrow"
#define  hgiupradarrowtradable " Tradable Rad up arrow"
#define  hgidownradarrowtradable " Tradable Rad down arrow"
#define  hgiupradarrowuntradable " Untradable Rad up arrow"
#define  hgidownradarrowuntradable " Untradable Rad down arrow"
#define  hgibluewavylong " Blue wavy long"
#define  hgibluewavyshort " Blue wavy short"
#define  hgiyellowrangewavey " Yellow range wavey"

#define  AllTrades 10 //Tells CloseAllTrades() to close/delete everything
#define  million 1000000;

//Define the FifoBuy/SellTicket fields
#define  TradeOpenTime 0
#define  TradeTicket 1
#define  TradeProfitCash 2 //Cash profit
#define  TradeProfitPips 3 //Pips profit

//Define the GridBuy/SellTicket fields
#define  TradeOpenPrice 0
//#define  TradeTicket 1 /// can use the one above.

//Pending trade price line
#define  pendingpriceline "Pending price line"
//Hidden sl and tp lines. If used, the bot will close trades on a touch/break of these lines.
//Each line is named with its appropriate prefix and the ticket number of the relevant trade
#define  TpPrefix "Tp"
#define  SlPrefix "Sl"

//Error reporting
#define  slm " stop loss modification failed with error "
#define  tpm " take profit modification failed with error "
#define  ocm " order close failed with error "
#define  odm " order delete failed with error "
#define  pcm " part close failed with error "
#define  spm " shirt-protection close failed with error "
#define  slim " stop loss insertion failed with error "
#define  tpim " take profit insertion failed with error "
#define  tpsl " take profit or stop loss insertion failed with error "
#define  oop " pending order price modification failed with error "

extern string  gen="----General inputs----";
/*
Note to coders about TradingTimeFrame. Be consistent in your calls to indicators etc and always use TradingTimeFrame i.e.
double v = iClose(Symbol(), TradingTimeFrame, shift) instead of Close[shift].
This allows the user to change time frames without disturbing the ea. There is a line of code in OnInit(), just above the call
to DisplayUserFeedback() that forces the EA to wait until the open of a new TradingTimeFrame candle; you might want to comment
this out during your EA development.
*/
extern ENUM_TIMEFRAMES  TradingTimeFrame              = PERIOD_H1;
extern ENUM_TIMEFRAMES  LookForNewTradeCycle          = PERIOD_M15;
bool                    EveryTickMode                 = false;
extern double           Lot                           = 0.01;
extern double           RiskPercent                   = 0;              // Set to zero to disable and use Lot
extern double           LotsPerDollopOfCash           = 0;              // Over rides Lot. Zero input to cancel.
extern double           SizeOfDollop                  = 1000;
extern bool             UseBalance                    = false;
extern bool             UseEquity                     = true;
extern bool             StopTrading                   = false;
extern bool             TradeLong                     = true;
extern bool             TradeShort                    = true;
extern int              TakeProfitPips                = 0;
extern int              StopLossPips                  = 0;
extern int              MagicNumber                   = 54321;
extern string           TradeComment                  = "HGSSCB";
string                  TradeDetailComment            = "";
extern bool             IsGlobalPrimeOrECNCriminal    = true;
extern double           MaxSlippagePips               = 5;
                        //We need more safety to combat the cretins at Crapperquotes managing to break Matt's OR code occasionally.
                        //EA will make no further attempt to trade for PostTradeAttemptWaitMinutes minutes, whether OR detects a receipt return or not.
extern int              PostTradeAttemptWaitSeconds   = 600;            // Defaults to 10 minutes
extern bool             WriteFileForTestDatabase      = false;
////////////////////////////////////////////////////////////////////////////////////////
datetime                TimeToStartTrading=0;                           // Re-start calling LookForTradingOpportunities() at this time.
double                  TakeProfit, StopLoss;
datetime                OldBarsTime;
double                  dPriceFloor = 0, dPriceCeiling = 0;             // Next x0 numbers
double                  PriceCeiling100 = 0, PriceFloor100 = 0;         // Next 'big' numbers

string                  GvName="Under management flag";                 //The name of the GV that tells the EA not to send trades whilst the manager is closing them.
                        //'Close all trades this pair only script' sets a GV to tell EA's not to attempt a trade during closure
string                  LocalGvName = "Local closure in operation " + Symbol();
                        //'Nuclear option script' sets a GV to tell EA's not to attempt a trade during closure
string                  NuclearGvName = "Nuclear option closure in operation " + Symbol();

string                  TradingTimeFrameDisplay="";
string                  SRTimeFrameDisplay="";//UseSuppRes
                        //For FIFO
int                     FifoTicket[];//Array to store trade ticket numbers in FIFO mode, to cater for
                                     //US citizens and to make iterating through the trade closure loop
                                     //quicker.
                        //An array to store ticket numbers of trades that need closing, should an offsetting OrderClose fail
double                  ForceCloseTickets[];
bool                    RemoveExpert=false;
////////////////////////////////////////////////////////////////////////////////////////

extern string           sep2="================================================================";
extern string           spc="---- Candle inputs ----";
extern int              NoOfCandles                   = 2;
extern bool             UseCandleSequenceForSL        = false;
extern double           RatioOfSlForTP                = 2;              // Default ratio is double the SL. Zero value disables this.
extern double           PercentageOfSlForTP           = 0;              // A percentage of the SL for the TP. Zero value disables this.
extern int              MaxTradesAllowed              = 3;              // For multi-trade EA's
extern bool             CloseTradesOnOppositeSignal   = true;           // Close buys on a sell signal and vice versa
extern string           pbt="-- Pullback trading --";
extern bool             TradeThePullback              = true;           // Allows trade in the opposite direction to the main trading direction
                                                                        // following a pullback
extern bool             OnlyTradeThePullback          = false;
extern int              NoOfCandlesToMeasurePullback  = 2;
extern int              PullbackTradeStopLossPips     = 0;
extern int              PullbackTradeTakeProfitPips   = 0;
extern string           mdt="-- Distance between trades --";
extern double           MinDistanceBetweenTrades      = 10;
int ups = 0;
int downs = 0;
////////////////////////////////////////////////////////////////////////////////////////
string                  OverallCandleDirection="";                      // Direction of the last NoOfCandles
string                  PreviousCandleDirection[];                      // Direction of the individual candles. Sized in OnInit()
bool                    PullBackTrade=false;                            // Set to true when the trade is a pullback. Set in ReadIndicatorValues()
double                  PullbackTradeStopLoss=0, PullbackTradeTakeProfit=0;
string                  OverallPullbackCandleDirection="";              // Direction of the last NoOfCandles
////////////////////////////////////////////////////////////////////////////////////////

extern string           sep2a="================================================================";
extern string           bas="---- Basket trading ----";
extern bool             BasketTrading                 = true;           // This will send the trades without stop loss or take profit
extern int              BasketTakeProfitPips          = 0;              // Zero to disable
extern int              BasketTakeProfitCash          = 5;              // Zero to disable

extern string           sep1h="================================================================";
extern string           chgi="---- HGI ----";
extern string           thgi="---- Common inputs ----";                 // Common to all three time frames
extern bool             TradeTrendArrows              = true;
extern bool             TradeBlueWavyLines            = true;
extern bool             YellowRangeLinePreventsTrading= true;
extern bool             HgiCloseOnOppositeSignal      = false;          // All three time frames have an opposite direction signal.
////////////////////////////////////////////////////////////////////////////////////////
string                  AllSignals="";                                  //Up down or mixed
////////////////////////////////////////////////////////////////////////////////////////

extern string           HtfHGI="-- HGI High time frame --";
extern bool             UseHtfHGI                     = true;
extern ENUM_TIMEFRAMES  HtfTimeFrame                  = PERIOD_D1;
extern ENUM_TIMEFRAMES  HGIHtfReadCycle               = PERIOD_H1;
extern bool             HtfCloseOnOppositeSignal      = true;
extern bool             HtfCloseOnYellowWavey         = false;
////////////////////////////////////////////////////////////////////////////////////////
string                  HtfHgiStatus="";
////////////////////////////////////////////////////////////////////////////////////////

extern string           MtfHGI="-- HGI Medium time frame --";
extern bool             UseMtfHGI                     = true;
extern ENUM_TIMEFRAMES  MtfTimeFrame                  = PERIOD_H4;
extern ENUM_TIMEFRAMES  HGIMtfReadCycle               = PERIOD_H1;
extern bool             MtfCloseOnOppositeSignal      = true;
extern bool             MtfCloseOnYellowWavey         = false;
////////////////////////////////////////////////////////////////////////////////////////
string                  MtfHgiStatus="";
////////////////////////////////////////////////////////////////////////////////////////

extern string           LtfHGI="-- HGI Low time frame --";
extern bool             UseLtfHGI                     = true;
extern ENUM_TIMEFRAMES  LtfTimeFrame                  = PERIOD_H1;
extern ENUM_TIMEFRAMES  HGILtfReadCycle               = PERIOD_M15;
extern bool             LtfCloseOnOppositeSignal      = true;
extern bool             LtfCloseOnYellowWavey         = false;
////////////////////////////////////////////////////////////////////////////////////////
string                  LtfHgiStatus="";
////////////////////////////////////////////////////////////////////////////////////////

extern string           sep1a="================================================================";
extern string           ssl="---- Super Slope ----";
extern string           SSCommon="---- Common Inputs ----";
extern bool             CloseTradesOnSsReversal       = true;            // Close trades if all tf's are in the wrong direction
extern string           HtfSS="-- SS High time frame --";
extern bool             UseHtfSS                      = true;
extern ENUM_TIMEFRAMES  HtfSsTimeFrame                = PERIOD_D1;
extern ENUM_TIMEFRAMES  SSHtfReadCycle                = PERIOD_H1;
extern double           HtfSsDifferenceThreshold      = 1.0;
double                  HtfSsLevelCrossValue          = 1.0;
extern int              HtfSsSlopeMAPeriod            = 7;
extern int              HtfSsSlopeATRPeriod           = 50;
extern double           HtfMinimumBuyValue            = 1;
extern double           HtfMinimumSellValue           = -1;
extern bool             HtfSSCloseOnOppositeSignal    = false;
////////////////////////////////////////////////////////////////////////////////////////
string                  HtfSsStatus="";                                 // Colours defined at top of file
double                  HtfSsVal=0;
string                  AllColours="";                                  // mixed, red or blue;
////////////////////////////////////////////////////////////////////////////////////////

extern string           MtfSS="-- SS Medium time frame --";
extern bool             UseMtfSS                      = true;
extern ENUM_TIMEFRAMES  MtfSsTimeFrame                = PERIOD_H4;
extern ENUM_TIMEFRAMES  SSMtfReadCycle                = PERIOD_H1;
extern double           MtfSsDifferenceThreshold      = 1.0;
double                  MtfSsLevelCrossValue          = 1.0;
extern int              MtfSsSlopeMAPeriod            = 7;
extern int              MtfSsSlopeATRPeriod           = 50;
extern double           MtfMinimumBuyValue            = 1;
extern double           MtfMinimumSellValue           = -1;
extern bool             MtfSSCloseOnOppositeSignal    = false;
////////////////////////////////////////////////////////////////////////////////////////
string                  MtfSsStatus="";                                 // Colours defined at top of file
double                  MtfSsVal=0;
////////////////////////////////////////////////////////////////////////////////////////

extern string           LtfSS="-- SS Low time frame --";
extern bool             UseLtfSS                      = true;
extern ENUM_TIMEFRAMES  LtfSsTimeFrame                = PERIOD_H1;
extern ENUM_TIMEFRAMES  SSLtfReadCycle                = PERIOD_M15;
extern double           LtfSsDifferenceThreshold      = 1.0;
double                  LtfSsLevelCrossValue          = 1.0;
extern int              LtfSsSlopeMAPeriod            = 7;
extern int              LtfSsSlopeATRPeriod           = 50;
extern double           LtfMinimumBuyValue            = 1;
extern double           LtfMinimumSellValue           = -1;
extern bool             LtfSSCloseOnOppositeSignal    = false;
////////////////////////////////////////////////////////////////////////////////////////
string                  LtfSsStatus="";                                 // Colours defined at top of file
double                  LtfSsVal=0;
////////////////////////////////////////////////////////////////////////////////////////

extern string           sep17="================================================================";
extern string           SR="---- Support and Resistance inputs ----";
extern bool             UseSuppRes                    = true;
extern ENUM_TIMEFRAMES  SRTimeFrame                   = PERIOD_H1;

extern bool             UseResHighforBuyTP            = false;
extern bool             UseResLowforBuyTP             = true;
extern bool             UseSupHighforBuySL            = false;
extern bool             UseSupLowforBuySL             = true;

extern bool             UseSupHighforSellTP           = true;
extern bool             UseSupLowforSellTP            = false;
extern bool             UseResHighforSellSL           = true;
extern bool             UseResLowforSellSL            = false;

extern bool             ShowAlertWhenTradeCloses      = true;

extern bool             DontOpenTradesInsideSRZones   = true;
extern bool             OpenSomeTradesInsideSRZones   = true;
extern int              SRBuffer = 10;
////////////////////////////////////////////////////////////////////////////////////////
                        //Variables to hold the zone information
double                  res_hi=0, res_lo=0, sup_hi=0, sup_lo=0;
int                     res_strength=0, sup_strength=0;
int                     sup_zone=0, res_zone=0;
////////////////////////////////////////////////////////////////////////////////////////

extern string           sep1b="================================================================";
extern string           sfs="---- SafetyFeature ----";
                        //Safety feature. Sometimes an unexpected concatenation of inputs choice and logic error can cause rapid opening-closing of trades.
                        // Use the next input in combination with TooClose() to abort the trade if the previous one closed within the time limit.
extern int              MinMinutesBetweenTradeOpenClose=1;              //For spotting possible rogue trades
extern int              MinMinutesBetweenTrades=60;                     //Minimum time to pass after a trade closes, until the ea can open another.
////////////////////////////////////////////////////////////////////////////////////////
bool                    SafetyViolation               = false;          // For chart display
bool                    RobotSuspended                = false;
////////////////////////////////////////////////////////////////////////////////////////

extern string           sep3="================================================================";
                        //Hidden tp/sl inputs.
extern string           hts="---- Stealth stop loss and take profit inputs ----";
extern int              PipsHiddenFromCriminal        = 0;              // Added to the 'hard' sl and tp and used for closure calculations
////////////////////////////////////////////////////////////////////////////////////////
double                  HiddenStopLoss,HiddenTakeProfit;
double                  HiddenPips=0;                                   //Added to the 'hard' sl and tp and used for closure calculations
////////////////////////////////////////////////////////////////////////////////////////


extern string           sep7="================================================================";
                        //CheckTradingTimes. Baluda has provided all the code for this. Mny thanks Paul; you are a star.
extern string           trh = "----Trading hours----";
extern string           tr1 = "tradingHours is a comma delimited list";
extern string           tr1a="of start and stop times.";
extern string           tr2="Prefix start with '+', stop with '-'";
extern string           tr2a="Use 24H format, breker's server time.";
extern string           tr3="Example: '+07.00,-10.30,+14.15,-16.00'";
extern string           tr3a="Do not leave spaces";
extern string           tr4="Blank input means 24 hour trading.";
extern string           tradingHours                  = "";
extern bool             CloseTradesOutsideTradeTimes  = true;
////////////////////////////////////////////////////////////////////////////////////////
double                  TradeTimeOn[];
double                  TradeTimeOff[];
                        // Trading hours variables
int                     tradeHours[];
string                  tradingHoursDisplay;                            // tradingHours is reduced to "" on initTradingHours,
bool                    TradeTimeOk;                                    // so this variable saves it for screen display.
////////////////////////////////////////////////////////////////////////////////////////

extern string           sess1="================================================================";
                        //These can be used in conjunction with Paul's trading hours to draw vertical session start lines and horizontal open prices
extern string           ses="---- Session line drawing inputs ----";
extern bool             DrawSessionStartLine          = true;
extern color            SessionStartLineColour        = Yellow;
extern bool             DrawSessionOpenPriceLine      = true;
extern color            SessionOpenPriceLineColour    = Yellow;
////////////////////////////////////////////////////////////////////////////////////////
string                  SessionStartLineName="Session start line";
string                  SessionOpenPriceLineName="Session Open Price Line";
double                  StartHours[];
string                  MarketTradingStatus="";                         // no movement, long direction or short direction
////////////////////////////////////////////////////////////////////////////////////////

extern string           sep1de="================================================================";
extern string           fssmt="---- Inputs applied to individual days ----";
extern int              FridayStopTradingHour         = 24;             // Ignore signals at and after this time on Friday.
                                                                        // Local time input. >23 to disable.
extern int              SaturdayStopTradingHour       = 4;              // For those in Upside Down Land.
extern bool             TradeSundayCandle             = false;
extern int              MondayStartHour               = 8;              // 24h local time
extern bool             TradeThursdayCandle           = true;           // Thursday tends to be a reversal day, so avoid it.

                        //This code by tomele. Thank you Thomas. Wonderful stuff.
extern string           sep7b="================================================================";
extern string           roll="---- Rollover time ----";
extern bool             DisableEaDuringRollover=true;
extern string           ro1 = "Use 24H format, SERVER time.";
extern string           ro2 = "Example: '23.55'";
extern string           RollOverStarts                = "23.55";
extern string           RollOverEnds                  = "00.15";
////////////////////////////////////////////////////////////////////////////////////////
bool                    RolloverInProgress=false;                       // Tells DisplayUserFeedback() to display the rollover message
////////////////////////////////////////////////////////////////////////////////////////

extern string           sep8="================================================================";
extern string           bf="----Trading balance filters----";
extern bool             UseZeljko                     = false;
extern bool             OnlyTradeCurrencyTwice        = false;
////////////////////////////////////////////////////////////////////////////////////////
bool                    CanTradeThisPair;
////////////////////////////////////////////////////////////////////////////////////////

extern string           sep9="================================================================";
extern string           pts="----Swap filter----";
extern bool             CadPairsPositiveOnly          = false;
extern bool             AudPairsPositiveOnly          = false;
extern bool             NzdPairsPositiveOnly          = false;
extern bool             OnlyTradePositiveSwap         = false;
////////////////////////////////////////////////////////////////////////////////////////
double                  LongSwap,ShortSwap;
////////////////////////////////////////////////////////////////////////////////////////

extern string           sep10="================================================================";
extern string           amc="----Available Margin checks----";
extern string           sco="Scoobs";
extern bool             UseScoobsMarginCheck          = false;
extern string           fk="ForexKiwi";
extern bool             UseForexKiwi                  = false;
extern int              FkMinimumMarginPercent        = 1500;
////////////////////////////////////////////////////////////////////////////////////////
bool                    EnoughMargin;
string                  MarginMessage;
////////////////////////////////////////////////////////////////////////////////////////

extern string           sep11="================================================================";
extern string           asi="----Average spread inputs----";
bool                    RunInSpreadDetectionMode      = false;
extern int              TicksToCount                  = 5;              // The ticks to count whilst canculating the av spread
extern double           MultiplierToDetectStopHunt    = 10;
////////////////////////////////////////////////////////////////////////////////////////
double                  AverageSpread=0;
string                  SpreadGvName;                                   //A GV will hold the calculated average spread
int                     CountedTicks=0;                                 //For status display whilst calculating the spread
double                  BiggestSpread=0;                                //Holds a record of the widest spread since the EA was loaded
////////////////////////////////////////////////////////////////////////////////////////

extern string           sep11a="================================================================";
extern string           ccs="---- Chart snapshots ----";
extern bool             TakeSnapshots                 = false;          // Tells ea to take snaps when it opens and closes a trade
extern int              PictureWidth                  = 800;
extern int              PictureHeight                 = 600;

extern string           sep12="================================================================";
extern string           ems="----Email thingies----";
extern bool             EmailTradeNotification        = false;
extern bool             SendAlertNotTrade             = false;
extern bool             AlertPush                     = false;          // Enable to send push notification on alert
////////////////////////////////////////////////////////////////////////////////////////
bool                    AlertSent;                                      //To alert to a trade trigger without actually sending the trade
////////////////////////////////////////////////////////////////////////////////////////

extern string           sep13="================================================================";
extern string           tmm="----Trade management module----";
                        //Breakeven has to be enabled for JS and TS to work.
extern string           BE="Break even settings";
extern bool             BreakEven                     = true;
extern int              BreakEvenTargetPips           = 15;
extern int              BreakEvenTargetProfit         = 5;
extern bool             PartCloseEnabled              = false;
extern double           PartClosePercent              = 50;             // Percentage of the trade lots to close
////////////////////////////////////////////////////////////////////////////////////////
double                  BreakEvenPips,BreakEvenProfit;
bool                    TradeHasPartClosed=false;
////////////////////////////////////////////////////////////////////////////////////////

extern string           sep14="================================================================";
extern string           JSL="Jumping stop loss settings";
extern bool             JumpingStop                   = false;
extern int              JumpingStopTargetPips         = 10;
extern bool             AddBEP                        = true;
////////////////////////////////////////////////////////////////////////////////////////
double                  JumpingStopPips;
////////////////////////////////////////////////////////////////////////////////////////

extern string           sep15="================================================================";
extern string           cts="----Candlestick jumping stop----";
extern bool             UseCandlestickTrailingStop    = false;
extern int              CstTimeFrame                  = 0;              // Defaults to current chart
extern int              CstTrailCandles               = 1;              // Defaults to previous candle
extern bool             TrailMustLockInProfit         = true;
////////////////////////////////////////////////////////////////////////////////////////
int                     OldCstBars;                                     //For candlestick ts
////////////////////////////////////////////////////////////////////////////////////////

extern string           sep16="================================================================";
extern string           TSL="Trailing stop loss settings";
extern bool             TrailingStop                  = false;
extern int              TrailingStopTargetPips        = 20;
////////////////////////////////////////////////////////////////////////////////////////
double                  TrailingStopPips;
////////////////////////////////////////////////////////////////////////////////////////

                        //Enhanced screen feedback display code provided by Paul Batchelor (lifesys). Thanks Paul; this is fantastic.
extern string           se52  ="================================================================";
extern string           oad               ="----Odds and ends----";
extern int              ChartRefreshDelaySeconds      = 3;
extern int              DisplayGapSize                = 30;             // if using Comments
                        // ****************************** added to make screen Text more readable
extern bool             DisplayAsText                 = true;           // replaces Comment() with OBJ_LABEL text
extern bool             KeepTextOnTop                 = true;           // Disable the chart in foreground CrapTx setting so the candles do not obscure the text
extern int              DisplayX                      = 100;
extern int              DisplayY                      = 0;
extern int              fontSize                      = 8;
extern string           fontName                      = "Arial";
extern color            colour                        = Yellow;
////////////////////////////////////////////////////////////////////////////////////////
int                     DisplayCount;
string                  Gap,ScreenMessage;
////////////////////////////////////////////////////////////////////////////////////////
//And by Steve. I have pinched Tomasso's APTM function for returning the value of factor. Thanks Tommaso
double         factor;                                                  //For pips/points stuff. Set up in int init()
////////////////////////////////////////////////////////////////////////////////////////

//Matt's O-R stuff
int            O_R_Setting_max_retries=10;
double         O_R_Setting_sleep_time=4.0;                              // seconds
double         O_R_Setting_sleep_max=15.0;                              // seconds
int            RetryCount=10;                                           //Will make this number of attempts to get around the trade context busy error.


//Running total of trades
int            LossTrades,WinTrades;
double         OverallProfit;

//Misc
int            OldBars;
string         PipDescription=" pips";
bool           ForceTradeClosure;
int            TurnOff=0;                                               //For turning off functions without removing their code

//Variables for building a picture of the open position
int            MarketTradesTotal=0;                                     //Total of open market trades
//Market Buy trades
bool           BuyOpen=false;
int            MarketBuysCount=0;
double         LatestBuyPrice=0, EarliestBuyPrice=0, HighestBuyPrice=0, LowestBuyPrice=0;
int            BuyTicketNo=-1, HighestBuyTicketNo=-1, LowestBuyTicketNo=-1, LatestBuyTicketNo=-1, EarliestBuyTicketNo=-1;
double         BuyPipsUpl=0;
double         BuyCashUpl=0;
datetime       LatestBuyTradeTime=0;
datetime       EarliestBuyTradeTime=0;

//Market Sell trades
bool           SellOpen=false;
int            MarketSellsCount=0;
double         LatestSellPrice=0, EarliestSellPrice=0, HighestSellPrice=0, LowestSellPrice=0;
int            SellTicketNo=-1, HighestSellTicketNo=-1, LowestSellTicketNo=-1, LatestSellTicketNo=-1, EarliestSellTicketNo=-1;;
double         SellPipsUpl=0;
double         SellCashUpl=0;
datetime       LatestSellTradeTime=0;
datetime       EarliestSellTradeTime=0;

//BuyStop trades
bool           BuyStopOpen=false;
int            BuyStopsCount=0;
double         LatestBuyStopPrice=0, EarliestBuyStopPrice=0, HighestBuyStopPrice=0, LowestBuyStopPrice=0;
int            BuyStopTicketNo=-1, HighestBuyStopTicketNo=-1, LowestBuyStopTicketNo=-1, LatestBuyStopTicketNo=-1, EarliestBuyStopTicketNo=-1;;
datetime       LatestBuyStopTradeTime=0;
datetime       EarliestBuyStopTradeTime=0;

//BuyLimit trades
bool           BuyLimitOpen=false;
int            BuyLimitsCount=0;
double         LatestBuyLimitPrice=0, EarliestBuyLimitPrice=0, HighestBuyLimitPrice=0, LowestBuyLimitPrice=0;
int            BuyLimitTicketNo=-1, HighestBuyLimitTicketNo=-1, LowestBuyLimitTicketNo=-1, LatestBuyLimitTicketNo=-1, EarliestBuyLimitTicketNo=-1;;
datetime       LatestBuyLimitTradeTime=0;
datetime       EarliestBuyLimitTradeTime=0;

/////SellStop trades
bool           SellStopOpen=false;
int            SellStopsCount=0;
double         LatestSellStopPrice=0, EarliestSellStopPrice=0, HighestSellStopPrice=0, LowestSellStopPrice=0;
int            SellStopTicketNo=-1, HighestSellStopTicketNo=-1, LowestSellStopTicketNo=-1, LatestSellStopTicketNo=-1, EarliestSellStopTicketNo=-1;;
datetime       LatestSellStopTradeTime=0;
datetime       EarliestSellStopTradeTime=0;

//SellLimit trades
bool           SellLimitOpen=false;
int            SellLimitsCount=0;
double         LatestSellLimitPrice=0, EarliestSellLimitPrice=0, HighestSellLimitPrice=0, LowestSellLimitPrice=0;
int            SellLimitTicketNo=-1, HighestSellLimitTicketNo=-1, LowestSellLimitTicketNo=-1, LatestSellLimitTicketNo=-1, EarliestSellLimitTicketNo=-1;;
datetime       LatestSellLimitTradeTime=0;
datetime       EarliestSellLimitTradeTime=0;

//Not related to specific order types
int            TicketNo=-1,OpenTrades,OldOpenTrades;
//Variables to tell the ea that it has a trading signal
bool           BuySignal=false, SellSignal=false;
//Variables to tell the ea that it has a trading closure signal
bool           BuyCloseSignal=false, SellCloseSignal=false;
//Variables for storing market trade ticket numbers
datetime       LatestTradeTime=0, EarliestTradeTime=0;                  //More specific times are in each individual section
int            LatestTradeTicketNo=-1, EarliestTradeTicketNo=-1;
double         PipsUpl;                                                 //For keeping track of the pips PipsUpl of multi-trade/hedged positions
double         CashUpl;                                                 //For keeping track of the cash PipsUpl of multi-trade/hedged positions
//Variable for the hedging code to tell if there are tp's and sl's set
bool           TpSet=false, SlSet=false;

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DisplayUserFeedback()
{

   if(IsTesting() && !IsVisualMode()) return;

   string text = "";
   int cc = 0;

   //cpu saving
   static datetime CurrentTime = 0;
   static datetime DisplayNow = 0;
   if (TimeCurrent() < DisplayNow )
      return;
   CurrentTime = TimeCurrent();
   DisplayNow = CurrentTime + ChartRefreshDelaySeconds;

//   ************************* added for OBJ_LABEL
   DisplayCount = 1;
   removeAllObjects();
//   *************************

   ScreenMessage="";
   //ScreenMessage = StringConcatenate(ScreenMessage,Gap + NL);
   SM(NL);
   if(SafetyViolation) SM("*************** CANNOT TRADE YET. TOO SOON AFTER CLOSE OF PREVIOUS TRADE ***************"+NL);

   SM("Updates for this EA are to be found at http://www.stevehopwoodforex.com"+NL);
   SM("Feeling generous? Help keep the coder going with a small Paypal donation to pianodoodler@hotmail.com"+NL);
   SM("Broker time = "+TimeToStr(TimeCurrent(),TIME_DATE|TIME_SECONDS)+": Local time = "+TimeToStr(TimeLocal(),TIME_DATE|TIME_SECONDS)+NL);
   SM(version+NL);
/*
   //Code for time to bar-end display donated by Baluda. Cheers Paul.
   SM( TimeToString( iTime(Symbol(), TradingTimeFrame, 0) + TradingTimeFrame * 60 - CurTime(), TIME_MINUTES|TIME_SECONDS )
   + " left to bar end" + NL );
   */
   if(!TradeTimeOk)
   {
      SM(NL);
      SM("---------- OUTSIDE TRADING HOURS. Will continue to monitor opent trades. ----------"+NL+NL);
   }//if (!TradeTimeOk)

   if(RolloverInProgress)
   {
      SM(NL);
      SM("---------- ROLLOVER IN PROGRESS. I am taking no action until "+RollOverEnds+" ----------"+NL+NL);
      return;
   }//if (RolloverInProgress)

   SM(NL);

   text = "HGI: ";

   if (UseHtfHGI)
      text = text + "Htf " + HtfHgiStatus;
   if (UseMtfHGI)
      text = text + ": Mtf " + MtfHgiStatus;
   if (UseLtfHGI)
      text = text + ": Ltf " + LtfHgiStatus;
   text = text + ": Overall = " + AllSignals;
   SM(text + NL);

   int NoOfCandlesToShow = NoOfCandles;
   if (TradeThePullback || OnlyTradeThePullback)
      NoOfCandlesToShow = NoOfCandlesToMeasurePullback;
   text = "Previous candle directions: ";
   for (cc = NoOfCandlesToShow; cc >= 0; cc--)
   {
      text = text + PreviousCandleDirection[cc];
   }//for (cc = NoOfCandlesToShow; cc > 0; cc--)
   text = text + ":   Overall direction: " + OverallCandleDirection;
   SM(text + NL);
   if (!OnlyTradeThePullback)
   {
      text = "Taking regular trades. ";
      if (TradeThePullback)
         text = text + "Taking pullback trades.";
   }//if (!OnlyTradeThePullback)

   if (OnlyTradeThePullback)
      text = "Only taking pullback trades.";
   SM(text + NL);
   if (TradeThePullback || OnlyTradeThePullback)
   {
      text = "Overall pullback candle direction: " + OverallPullbackCandleDirection;
      SM(text + NL);
      SM("Pullback stop loss = " + PullbackTradeStopLossPips + " pips. Pullback take profit = " + PullbackTradeTakeProfitPips + " pips" + NL);
   }

   SM(NL);

   if(UseSuppRes)
   {
      SM("Support and Resistance Timeframe: " + SRTimeFrameDisplay + NL);
      text = "Resistance: ";
      if (res_zone >= 0)
         text = text + DoubleToStr(res_hi, Digits) + " / " + DoubleToStr(res_lo,Digits) + " - Strength: " + res_strength +" ";
      else
         text = text + "No Resistance Found";
         SM(text + NL);

      text = "Support:       ";
      if (sup_zone >= 0)
         text = text + DoubleToStr(sup_hi, Digits) + " / " + DoubleToStr(sup_lo,Digits) + " - Strength: " + sup_strength;
      else
         text = text + "No Support Found";
      SM(text + NL);

      if (DontOpenTradesInsideSRZones || OpenSomeTradesInsideSRZones)
      {
         if (DontOpenTradesInsideSRZones)
            text = "Trades will not be opened inside support or resistance zones";
         if (OpenSomeTradesInsideSRZones)
            text = "Buy trades will be opened inside support zones. Sells will be opened in resistance zones";
         if (AllSignals == up)
            if (Bid <= NormalizeDouble(res_hi, Digits) && Bid >= NormalizeDouble(res_lo, Digits))
               text = "Bid price inside resistance zone. Buys won't be opened";
            else if (!OpenSomeTradesInsideSRZones && Bid <= NormalizeDouble(sup_hi, Digits) && Bid >= NormalizeDouble(sup_lo, Digits))
                    text = "Bid price inside support zone. Buys won't be opened";
         if (AllSignals == down)
            if (!OpenSomeTradesInsideSRZones && Ask <= NormalizeDouble(res_hi, Digits) && Ask >= NormalizeDouble(res_lo, Digits))
               text = "Ask price inside resistance zone. Sells won't be opened";
            else if (Ask <= NormalizeDouble(sup_hi, Digits) && Ask >= NormalizeDouble(sup_lo, Digits))
                    text = "Ask price inside support zone. Sells won't be opened";
         SM(text + NL);
         SM(NL);
      }//if (DontOpenTradesInsideSRZones || OpenSomeTradesInsideSRZones)

   }//if(UseSuppRes)

   if (BasketTrading)
   {
      SM("Basket trading. Cash target = " + AccountCurrency() + IntegerToString(BasketTakeProfitCash)
         + ": Pips target = " + IntegerToString(BasketTakeProfitPips) + " pips " + NL );
   }//if (BasketTrading)

   SM(NL);
   text = "Market trades open = ";
   SM(text + IntegerToString(MarketTradesTotal) + ": Pips UPL = " + DoubleToStr(PipsUpl, 0)
   +  ": Cash UPL = " + DoubleToStr(CashUpl, 2) + NL);
   if (BuyOpen)
      SM("Buy trades = " + IntegerToString(MarketBuysCount)
         + ": Pips upl = " + IntegerToString(BuyPipsUpl)
         + ": Cash upl = " + DoubleToStr(BuyCashUpl, 2)
         + NL);
   if (SellOpen)
      SM("Sell trades = " + IntegerToString(MarketSellsCount)
         + ": Pips upl = " + IntegerToString(SellPipsUpl)
         + ": Cash upl = " + DoubleToStr(SellCashUpl,2)
         + NL);

   text = "No trade signal";
   if (BuySignal)
      text = "We have a buy signal";
   if (SellSignal)
      text = "We have a sell signal";
   SM(text + NL);

   SM(NL);
   SM("Trading time frame: " + TradingTimeFrameDisplay + NL);
   if (StopTrading)
      SM("Trading is stopped" + NL);
   if(TradeLong) SM("Taking long trades"+NL);
   if(TradeShort) SM("Taking short trades"+NL);
   if(!TradeLong && !TradeShort) SM("Both TradeLong and TradeShort are set to false"+NL);
   SM("Lot size: "+DoubleToStr(Lot,2)+" (Criminal's minimum lot size: "+DoubleToStr(MarketInfo(Symbol(),MODE_MINLOT),2)+")"+NL);
   if(!CloseEnough(TakeProfit,0)) SM("Take profit: "+DoubleToStr(TakeProfit,0)+PipDescription+NL);
   if(!CloseEnough(StopLoss,0)) SM("Stop loss: "+DoubleToStr(StopLoss,0)+PipDescription+NL);
   SM("Magic number: "+MagicNumber+NL);
   SM("Trade comment: "+TradeComment+NL);
   if(IsGlobalPrimeOrECNCriminal) SM("IsGlobalPrimeOrECNCriminal = true"+NL);
   else SM("IsGlobalPrimeOrECNCriminal = false"+NL);
   double spread=(Ask-Bid)*factor;
   SM("Average Spread = "+DoubleToStr(AverageSpread,1)+": Spread = "+DoubleToStr(spread,1)+": Widest since loading = "+DoubleToStr(BiggestSpread,1)+NL);
   SM("Long swap "+DoubleToStr(LongSwap,2)+": ShortSwap "+DoubleToStr(ShortSwap,2)+NL);
   SM(NL);

   //Trading hours
   if(tradingHoursDisplay!="") SM("Trading hours: "+tradingHoursDisplay+NL);
   else SM("24 hour trading: "+NL);

   if(MarginMessage!="") SM(MarginMessage+NL);

   //Running total of trades
   SM(Gap+NL);
   SM("Results today. Wins: "+WinTrades+": Losses "+LossTrades+": P/L "+DoubleToStr(OverallProfit,2)+NL);

   SM(NL);

   if(BreakEven)
   {
      SM("Breakeven is set to "+DoubleToStr(BreakEvenPips,0)+PipDescription+": BreakEvenProfit = "+DoubleToStr(BreakEvenProfit,0)+PipDescription);
      SM(NL);
      if(PartCloseEnabled)
      {
         double CloseLots=NormalizeLots(Symbol(),Lot *(PartClosePercent/100));
         SM("Part-close is enabled at "+DoubleToStr(PartClosePercent,2)+"% ("+DoubleToStr(CloseLots,2)+" lots to close)"+NL);
      }//if (PartCloseEnabled)
   }//if (BreakEven)

   if(UseCandlestickTrailingStop)
   {
      SM("Using candlestick trailing stop"+NL);
   }//if (UseCandlestickTrailingStop)

   if(JumpingStop)
   {
      SM("Jumping stop is set to "+DoubleToStr(JumpingStopPips,0)+PipDescription);
      SM(NL);
   }//if (JumpingStop)

   if(TrailingStop)
   {
      SM("Trailing stop is set to "+DoubleToStr(TrailingStopPips,0)+PipDescription);
      SM(NL);
   }//if (TrailingStop)


   Comment(ScreenMessage);

}//void DisplayUserFeedback()

//+--------------------------------------------------------------------+
//| Paul Bachelor's (lifesys) text display module to replace Comment()|
//+--------------------------------------------------------------------+
void SM(string message)
{
   if (DisplayAsText)
   {
      DisplayCount++;
      Display(message);
   }
   else
      ScreenMessage = StringConcatenate(ScreenMessage,Gap, message);

}//End void SM()

//   ************************* added for OBJ_LABEL
void removeAllObjects()
{
   for(int i = ObjectsTotal() - 1; i >= 0; i--)
   if (StringFind(ObjectName(i),"OAM-",0) > -1)
      ObjectDelete(ObjectName(i));
}//End void removeAllObjects()
//   ************************* added for OBJ_LABEL

void Display(string text)
{
    string lab_str = "OAM-" + IntegerToString(DisplayCount);
    double ofset = 0;
    string textpart[5];
    uint w,h;

    for (int cc = 0; cc < 5; cc++)
    {
       textpart[cc] = StringSubstr(text,cc*63,64);
       if (StringLen(textpart[cc]) ==0) continue;
       lab_str = lab_str + IntegerToString(cc);

       ObjectCreate(lab_str, OBJ_LABEL, 0, 0, 0);
       ObjectSet(lab_str, OBJPROP_CORNER, 0);
       ObjectSet(lab_str, OBJPROP_XDISTANCE, DisplayX + ofset);
       ObjectSet(lab_str, OBJPROP_YDISTANCE, DisplayY+DisplayCount*(int)(fontSize*1.5));
       ObjectSet(lab_str, OBJPROP_BACK, false);
       ObjectSetText(lab_str, textpart[cc], fontSize, fontName, colour);

       /////////////////////////////////////////////////
       //Calculate label size
       //Tomele supplied this code to eliminate the gaps in the text.
       //Thanks Thomas.
       TextSetFont(fontName,-fontSize*10,0,0);
       TextGetSize(textpart[cc],w,h);

       //Trim trailing space
       if (StringSubstr(textpart[cc],63,1)==" ")
          ofset+=(int)(w-fontSize*0.3);
       else
          ofset+=(int)(w-fontSize*0.7);
       /////////////////////////////////////////////////
    }//for (int cc = 0; cc < 5; cc++)
}//End void Display(string text)


bool ChartForegroundSet(const bool value,const long chart_ID=0)
{
//--- reset the error value
   ResetLastError();
//--- set property value
   if(!ChartSetInteger(chart_ID,CHART_FOREGROUND,0,value))
   {
      //--- display the error message in Experts journal
      Print(__FUNCTION__+", Error Code = ",GetLastError());
      return(false);
   }//if(!ChartSetInteger(chart_ID,CHART_FOREGROUND,0,value))
//--- successful execution
   return(true);
}//End bool ChartForegroundSet(const bool value,const long chart_ID=0)
//+--------------------------------------------------------------------+
//| End of Paul's text display module to replace Comment()             |
//+--------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
//----

   if(WriteFileForTestDatabase)
      ChartSaveTemplate(0,StringFormat("ZZT2MTPL-%s-%s-%s-%d-%d-%d-%d","SHF","HGCB",Symbol(),Period(),AccountNumber(),TimeCurrent(),MagicNumber));

   // TDesk code
   InitializeTDesk(TradeComment,MagicNumber);

//~ Set up the pips factor. tp and sl etc.
//~ The EA uses doubles and assume the value of the integer user inputs. This:
//~    1) minimises the danger of the inputs becoming corrupted by restarts;
//~    2) the integer inputs cannot be divided by factor - doing so results in zero.

   factor=GetPipFactor(Symbol());
   StopLoss=StopLossPips;
   TakeProfit=TakeProfitPips;
   BreakEvenPips=BreakEvenTargetPips;
   BreakEvenProfit = BreakEvenTargetProfit;
   JumpingStopPips = JumpingStopTargetPips;
   TrailingStopPips= TrailingStopTargetPips;
   HiddenPips=PipsHiddenFromCriminal;
   PullbackTradeStopLoss = PullbackTradeStopLossPips;
   PullbackTradeTakeProfit = PullbackTradeTakeProfitPips;
   TradeDetailComment = TradeComment;

   while(IsConnected()==false)
   {
      Comment("Waiting for MT4 connection...");
      Comment("");

      Sleep(1000);
   }//while (IsConnected()==false)

   //Size the PreviousCandleDirection array
   ArrayResize(PreviousCandleDirection, NoOfCandlesToMeasurePullback + 1);

   //User zone error check
   if (UseSuppRes)
      if (OpenSomeTradesInsideSRZones)
         DontOpenTradesInsideSRZones = false;//Needs to be to allow OpenSomeTradesInsideSRZones to work

   //Lot size and part-close idiot check for the cretins. Code provided by phil_trade. Many thanks, Philippe.
   //adjust Min_lot
   if (CloseEnough(RiskPercent, 0) )
      if(Lot<MarketInfo(Symbol(),MODE_MINLOT))
      {
         Alert(Symbol()+" Lot was adjusted to Minlot = "+DoubleToStr(MarketInfo(Symbol(),MODE_MINLOT),Digits));
         Lot=MarketInfo(Symbol(),MODE_MINLOT);
      }//if (Lot < MarketInfo(Symbol(), MODE_MINLOT))
/*
   //check Partial close parameters
   if (PartCloseEnabled == true)
   {
      if (Lot < Close_Lots + Preserve_Lots || Lot < MarketInfo(Symbol(), MODE_MINLOT) + Close_Lots )
      {
         Alert(Symbol()+" PartCloseEnabled is disabled because Lot < Close_Lots + Preserve_Lots or Lot < MarketInfo(Symbol(), MODE_MINLOT) + Close_Lots !");
         PartCloseEnabled = false;
      }//if (Lot < Close_Lots + Preserve_Lots || Lot < MarketInfo(Symbol(), MODE_MINLOT) + Close_Lots )
   }//if (PartCloseEnabled == true)
   */

   //Jumping/trailing stops need breakeven set before they work properly
   if ((JumpingStop || TrailingStop) && !BreakEven)
   {
      BreakEven = true;
      if (JumpingStop) BreakEvenPips = JumpingStopPips;
      if (TrailingStop) BreakEvenPips = TrailingStopPips;
   }//if (JumpingStop || TrailingStop)

   Gap="";
   if (DisplayGapSize >0)
   {
      for (int cc=0; cc< DisplayGapSize; cc++)
      {
         Gap = StringConcatenate(Gap, " ");
      }
   }//if (DisplayGapSize >0)

   //Reset CriminIsECN if crim is IBFX and the punter does not know or, like me, keeps on forgetting
   string name= TerminalCompany();
   int ispart = StringFind(name,"IBFX",0);
   if(ispart<0) ispart=StringFind(name,"Interbank FX",0);
   if(ispart>-1) IsGlobalPrimeOrECNCriminal=true;
   ispart=StringFind(name,"Global Prime",0);
   if(ispart>-1) IsGlobalPrimeOrECNCriminal=true;

   //Set up the trading hours
   tradingHoursDisplay=tradingHours;//For display
   initTradingHours();//Sets up the trading hours array

   if(TradeComment=="") TradeComment=" ";
   OldBars=Bars;
   TicketNo=-1;
   ReadIndicatorValues();//For initial display in case user has turned off constant re-display
   GetSwap(Symbol());//This will need editing/removing in a multi-pair ea.
   TradeDirectionBySwap();
   TooClose();
   CountOpenTrades();
   OldOpenTrades=OpenTrades;
   TradeTimeOk=CheckTradingTimes();

   //The apread global variable
   if (!IsTesting() )
   {
      SpreadGvName=Symbol()+" average spread";
      AverageSpread=GlobalVariableGet(SpreadGvName);//If no gv, then the value will be left at zero.
   }//if (!IsTesting() )

   //Chart display
   if (DisplayAsText)
      if (KeepTextOnTop)
         ChartForegroundSet(false,0);// change chart to background

   //Ensure that an ea depending on Close[1] for its values does not immediately fire a trade.
   if (!EveryTickMode) OldBarsTime = iTime(Symbol(), TradingTimeFrame, 0);

   //Lot size based on account size
   if (!CloseEnough(LotsPerDollopOfCash, 0))
      CalculateLotAsAmountPerCashDollops();

   //Time frame display
   TradingTimeFrameDisplay = GetTimeFrameDisplay(TradingTimeFrame);

   //SuppRes Time frame display
   if (UseSuppRes)
      SRTimeFrameDisplay = GetTimeFrameDisplay(SRTimeFrame);

   DisplayUserFeedback();

//----
   return(0);
}
//+------------------------------------------------------------------+
//| expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
//----
   Comment("");
   removeAllObjects();

   ObjectDelete(SessionStartLineName);
   ObjectDelete(SessionOpenPriceLineName);

   ArrayFree(StartHours);
   ArrayFree(PreviousCandleDirection);

   // TDesk code
   //DeleteTDeskSignals(Symbol() );

//----
   return;
}

string GetTimeFrameDisplay(int tf)
{

   if (tf == 0)
      tf = Period();

   if (tf == PERIOD_M1)
      return "M1";

   if (tf == PERIOD_M5)
      return "M5";

   if (tf == PERIOD_M15)
      return "M15";

   if (tf == PERIOD_M30)
      return "M30";

   if (tf == PERIOD_H1)
      return "H1";

   if (tf == PERIOD_H4)
      return "H4";

   if (tf == PERIOD_D1)
      return "D1";

   if (tf == PERIOD_W1)
      return "W1";

   if (tf == PERIOD_MN1)
      return "Monthly";

   return("No recognisable time frame selected");

}//string GetTimeFrameDisplay()

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool SendSingleTrade(string symbol,int type,string comment,double lotsize,double price,double stop,double take)
{

   double slippage=MaxSlippagePips*MathPow(10,Digits)/factor;
   int ticket = -1;

   color col=Red;
   if(type==OP_BUY || type==OP_BUYSTOP || type == OP_BUYLIMIT) col=Green;

   datetime expiry=0;
   //if (SendPendingTrades) expiry = TimeCurrent() + (PendingExpiryMinutes * 60);

   //RetryCount is declared as 10 in the Trading variables section at the top of this file
   for(int cc=0; cc<RetryCount; cc++)
     {
      //for (int d = 0; (d < RetryCount) && IsTradeContextBusy(); d++) Sleep(100);

      while(IsTradeContextBusy()) Sleep(100);//Put here so that excess slippage will cancel the trade if the ea has to wait for some time.

      RefreshRates();
      if(type == OP_BUY) price = MarketInfo(symbol, MODE_ASK);
      if(type == OP_SELL) price = MarketInfo(symbol, MODE_BID);


      if(!IsGlobalPrimeOrECNCriminal)
         ticket=OrderSend(symbol,type,lotsize,price,slippage,stop,take,comment,MagicNumber,expiry,col);

      //Is a 2 stage criminal
      if(IsGlobalPrimeOrECNCriminal)
      {
         ticket=OrderSend(symbol,type,lotsize,price,slippage,0,0,comment,MagicNumber,expiry,col);
         if(ticket>-1)
         {
            if (!CloseEnough(take, 0) || !CloseEnough(stop, 0))
               ModifyOrderTpSl(ticket,stop,take);
         }//if (ticket > 0)}
      }//if (IsGlobalPrimeOrECNCriminal)

      if(ticket>-1) break;//Exit the trade send loop
      if(cc == RetryCount - 1) return(false);

      //Error trapping for both
      if(ticket<0)
        {
         string stype;
         if(type == OP_BUY) stype = "OP_BUY";
         if(type == OP_SELL) stype = "OP_SELL";
         if(type == OP_BUYLIMIT) stype = "OP_BUYLIMIT";
         if(type == OP_SELLLIMIT) stype = "OP_SELLLIMIT";
         if(type == OP_BUYSTOP) stype = "OP_BUYSTOP";
         if(type == OP_SELLSTOP) stype = "OP_SELLSTOP";
         int err=GetLastError();
         Alert(symbol," ",WindowExpertName()," ",stype," order send failed with error(",err,"): ",ErrorDescription(err));
         Print(symbol," ",WindowExpertName()," ",stype," order send failed with error(",err,"): ",ErrorDescription(err));
         return(false);
        }//if (ticket < 0)
     }//for (int cc = 0; cc < RetryCount; cc++);

   TicketNo=ticket;
   //Make sure the trade has appeared in the platform's history to avoid duplicate trades.
   //My mod of Matt's code attempts to overcome the bastard crim's attempts to overcome Matt's code.
   bool TradeReturnedFromCriminal=false;
   while(!TradeReturnedFromCriminal)
     {
      TradeReturnedFromCriminal=O_R_CheckForHistory(ticket);
      if(!TradeReturnedFromCriminal)
        {
         Alert(Symbol()," sent trade not in your trade history yet. Turn of this ea NOW.");
        }//if (!TradeReturnedFromCriminal)
     }//while (!TradeReturnedFromCriminal)

   //Got this far, so trade send succeeded
   return(true);

}//End bool SendSingleTrade(int type, string comment, double lotsize, double price, double stop, double take)
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ModifyOrderTpSl(int ticket, double stop, double take)
{
   //Modifies an order already sent if the crim is ECN.

   if (CloseEnough(stop, 0) && CloseEnough(take, 0) ) return; //nothing to do

   if (!BetterOrderSelect(ticket, SELECT_BY_TICKET) ) return;//Trade does not exist, so no mod needed

   if (OrderCloseTime() > 0) return;//Somehow, we are examining a closed trade

   //In case some errant behaviour/code creates a tp the wrong side of the market, which would cause an instant close.
   if (OrderType() == OP_BUY && take < OrderOpenPrice() && !CloseEnough(take, 0) )
   {
      take = 0;
      ReportError(" ModifyOrder()", " take profit < market ");
   }//if (OrderType() == OP_BUY && take < OrderOpenPrice() )

   if (OrderType() == OP_SELL && take > OrderOpenPrice() )
   {
      take = 0;
      ReportError(" ModifyOrder()", " take profit < market ");
   }//if (OrderType() == OP_SELL && take > OrderOpenPrice() )

   //In case some errant behaviour/code creates a sl the wrong side of the market, which would cause an instant close.
   if (OrderType() == OP_BUY && stop > OrderOpenPrice() )
   {
      stop = 0;
      ReportError(" ModifyOrder()", " stop loss > market ");
   }//if (OrderType() == OP_BUY && take < OrderOpenPrice() )

   if (OrderType() == OP_SELL && stop < OrderOpenPrice()  && !CloseEnough(stop, 0) )
   {
      stop = 0;
      ReportError(" ModifyOrder()", " stop loss < market ");
   }//if (OrderType() == OP_SELL && take > OrderOpenPrice() )

   string Reason;
   //RetryCount is declared as 10 in the Trading variables section at the top of this file
   for (int cc = 0; cc < RetryCount; cc++)
   {
      for (int d = 0; (d < RetryCount) && IsTradeContextBusy(); d++) Sleep(100);
        if (!CloseEnough(take, 0) && !CloseEnough(stop, 0) )
        {
           while(IsTradeContextBusy()) Sleep(100);
           if (ModifyOrder(ticket, OrderOpenPrice(), stop, take, OrderExpiration(), clrNONE, __FUNCTION__, tpsl)) return;
        }//if (take > 0 && stop > 0)

        if (!CloseEnough(take, 0) && CloseEnough(stop, 0))
        {
           while(IsTradeContextBusy()) Sleep(100);
           if (ModifyOrder(ticket, OrderOpenPrice(), OrderStopLoss(), take, OrderExpiration(), clrNONE, __FUNCTION__, tpm)) return;
        }//if (take == 0 && stop != 0)

        if (CloseEnough(take, 0) && !CloseEnough(stop, 0))
        {
           while(IsTradeContextBusy()) Sleep(100);
           if (ModifyOrder(ticket, OrderOpenPrice(), stop, OrderTakeProfit(), OrderExpiration(), clrNONE, __FUNCTION__, slm)) return;
        }//if (take == 0 && stop != 0)
   }//for (int cc = 0; cc < RetryCount; cc++)

}//void ModifyOrderTpSl(int ticket, double tp, double sl)

//
//=============================================================================
bool O_R_CheckForHistory(int ticket)
  {
//My thanks to Matt for this code. He also has the undying gratitude of all users of my trading robots

   int lastTicket=OrderTicket();

   int cnt =0;
   int err=GetLastError(); // so we clear the global variable.
   err=0;
   bool exit_loop=false;
   bool success=false;
   int c = 0;

   while(!exit_loop)
     {
/* loop through open trades */
      int total=OrdersTotal();
      for(c=0; c<total; c++)
        {
         if(BetterOrderSelect(c,SELECT_BY_POS,MODE_TRADES)==true)
           {
            if(OrderTicket()==ticket)
              {
               success=true;
               exit_loop=true;
              }
           }
        }
      if(cnt>3)
        {
/* look through history too, as order may have opened and closed immediately */
         total=OrdersHistoryTotal();
         for(c=0; c<total; c++)
           {
            if(BetterOrderSelect(c,SELECT_BY_POS,MODE_HISTORY)==true)
              {
               if(OrderTicket()==ticket)
                 {
                  success=true;
                  exit_loop=true;
                 }
              }
           }
        }

      cnt=cnt+1;
      if(cnt>O_R_Setting_max_retries)
        {
         exit_loop=true;
        }
      if(!(success || exit_loop))
        {
         Print("Did not find #"+ticket+" in history, sleeping, then doing retry #"+cnt);
         O_R_Sleep(O_R_Setting_sleep_time,O_R_Setting_sleep_max);
        }
     }
// Select back the prior ticket num in case caller was using it.
   if(lastTicket>=0)
     {
      bool s = BetterOrderSelect(lastTicket,SELECT_BY_TICKET,MODE_TRADES);
     }
   if(!success)
     {
      Print("Never found #"+ticket+" in history! crap!");
     }
   return(success);
  }//End bool O_R_CheckForHistory(int ticket)

//
//=============================================================================
void O_R_Sleep(double mean_time, double max_time)
{
   if (IsTesting())
   {
      return;   // return immediately if backtesting.
   }

   double p = (MathRand()+1) / 32768.0;
   double t = -MathLog(p)*mean_time;
   t = MathMin(t,max_time);
   int ms = t*1000;
   if (ms < 10) {
      ms=10;
   }//if (ms < 10) {

   Sleep(ms);
}//End void O_R_Sleep(double mean_time, double max_time)

////////////////////////////////////////////////////////////////////////////////////////

bool IsTradingAllowed()
{
   //Returns false if any of the filters should cancel trading, else returns true to allow trading
   //Maximum spread
   if (!IsTesting() )
   {
      double spread = (Ask - Bid) * factor;
      if (spread > AverageSpread * MultiplierToDetectStopHunt) return(false);
   }//if (!IsTesting() )

   //An individual currency can only be traded twice, so check for this
   CanTradeThisPair = true;
   if (OnlyTradeCurrencyTwice && OpenTrades == 0)
   {
      IsThisPairTradable();
   }//if (OnlyTradeCurrencyTwice)
   if (!CanTradeThisPair) return(false);

   //Swap filter
   if (OpenTrades == 0) TradeDirectionBySwap();

   //Order close time safety feature
   if (TooClose()) return(false);

   return(true);

}//End bool IsTradingAllowed()

////////////////////////////////////////////////////////////////////////////////////////
//Balance/swap filters module
void TradeDirectionBySwap()
{

   //Sets TradeLong & TradeShort according to the positive/negative swap it attracts
   //Swap is read in init() and start()

   if (CadPairsPositiveOnly)
   {
      if (StringSubstrOld(Symbol(), 0, 3) == "CAD" || StringSubstrOld(Symbol(), 0, 3) == "cad" || StringSubstrOld(Symbol(), 3, 3) == "CAD" || StringSubstrOld(Symbol(), 3, 3) == "cad" )
      {
         if (LongSwap > 0) TradeLong = true;
         else TradeLong = false;
         if (ShortSwap > 0) TradeShort = true;
         else TradeShort = false;
      }//if (StringSubstrOld()
   }//if (CadPairsPositiveOnly)

   if (AudPairsPositiveOnly)
   {
      if (StringSubstrOld(Symbol(), 0, 3) == "AUD" || StringSubstrOld(Symbol(), 0, 3) == "aud" || StringSubstrOld(Symbol(), 3, 3) == "AUD" || StringSubstrOld(Symbol(), 3, 3) == "aud" )
      {
         if (LongSwap > 0) TradeLong = true;
         else TradeLong = false;
         if (ShortSwap > 0) TradeShort = true;
         else TradeShort = false;
      }//if (StringSubstrOld()
   }//if (AudPairsPositiveOnly)

   if (NzdPairsPositiveOnly)
   {
      if (StringSubstrOld(Symbol(), 0, 3) == "NZD" || StringSubstrOld(Symbol(), 0, 3) == "nzd" || StringSubstrOld(Symbol(), 3, 3) == "NZD" || StringSubstrOld(Symbol(), 3, 3) == "nzd" )
      {
         if (LongSwap > 0) TradeLong = true;
         else TradeLong = false;
         if (ShortSwap > 0) TradeShort = true;
         else TradeShort = false;
      }//if (StringSubstrOld()
   }//if (AudPairsPositiveOnly)

   //OnlyTradePositiveSwap filter
   if (OnlyTradePositiveSwap)
   {
      if (LongSwap < 0) TradeLong = false;
      if (ShortSwap < 0) TradeShort = false;
   }//if (OnlyTradePositiveSwap)

}//void TradeDirectionBySwap()
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsThisPairTradable()
{
   //Checks to see if either of the currencies in the pair is already being traded twice.
   //If not, then return true to show that the pair can be traded, else return false

   string c1 = StringSubstrOld(Symbol(), 0, 3);//First currency in the pair
   string c2 = StringSubstrOld(Symbol(), 3, 3);//Second currency in the pair
   int c1open = 0, c2open = 0;
   CanTradeThisPair = true;
   for (int cc = OrdersTotal() - 1; cc >= 0; cc--)
   {
      if (!BetterOrderSelect(cc, SELECT_BY_POS) ) continue;
      if (OrderSymbol() == Symbol() ) continue;//We can allow multiple trades on the same symbol
      if (OrderMagicNumber() != MagicNumber) continue;
      int index = StringFind(OrderSymbol(), c1);
      if (index > -1)
      {
         c1open++;
      }//if (index > -1)

      index = StringFind(OrderSymbol(), c2);
      if (index > -1)
      {
         c2open++;
      }//if (index > -1)

      if (c1open > 1 || c2open > 1)
      {
         CanTradeThisPair = false;
         return(false);
      }//if (c1open > 1 || c2open > 1)
   }//for (int cc = OrdersTotal() - 1; cc >= 0; cc--)

   //Got this far, so ok to trade
   return(true);

}//End bool IsThisPairTradable()

bool BalancedPair(int type)
{
   //Only allow an individual currency to trade if it is a balanced trade
   //e.g. UJ Buy open, so only allow Sell xxxJPY.
   //The passed parameter is the proposed trade, so an existing one must balance that

   //This code courtesy of Zeljko (zkucera) who has my grateful appreciation.

   string BuyCcy1, SellCcy1, BuyCcy2, SellCcy2;

   if (type == OP_BUY || type == OP_BUYSTOP || type == OP_BUYLIMIT)
   {
      BuyCcy1 = StringSubstrOld(Symbol(), 0, 3);
      SellCcy1 = StringSubstrOld(Symbol(), 3, 3);
   }//if (type == OP_BUY || type == OP_BUYSTOP)
   else
   {
      BuyCcy1 = StringSubstrOld(Symbol(), 3, 3);
      SellCcy1 = StringSubstrOld(Symbol(), 0, 3);
   }//else

   for (int cc = OrdersTotal() - 1; cc >= 0; cc--)
   {
      if (!BetterOrderSelect(cc, SELECT_BY_POS)) continue;
      if (OrderSymbol() == Symbol()) continue;
      if (OrderMagicNumber() != MagicNumber) continue;
      if (OrderType() == OP_BUY || OrderType() == OP_BUYSTOP || type == OP_BUYLIMIT)
      {
         BuyCcy2 = StringSubstrOld(OrderSymbol(), 0, 3);
         SellCcy2 = StringSubstrOld(OrderSymbol(), 3, 3);
      }//if (OrderType() == OP_BUY || OrderType() == OP_BUYSTOP)
      else
      {
         BuyCcy2 = StringSubstrOld(OrderSymbol(), 3, 3);
         SellCcy2 = StringSubstrOld(OrderSymbol(), 0, 3);
      }//else
      if (BuyCcy1 == BuyCcy2 || SellCcy1 == SellCcy2) return(false);
   }//for (int cc = OrdersTotal() - 1; cc >= 0; cc--)

   //Got this far, so it is ok to send the trade
   return(true);

}//End bool BalancedPair(int type)

//End Balance/swap filters module
////////////////////////////////////////////////////////////////////////////////////////
double CalculateLotSize(double price1,double price2)
{
   //Calculate the lot size by risk. Code kindly supplied by jmw1970. Nice one jmw.

   if(price1==0 || price2==0) return(Lot);//Just in case

   double FreeMargin= AccountFreeMargin();
   double TickValue = MarketInfo(Symbol(),MODE_TICKVALUE);
   double LotStep=MarketInfo(Symbol(),MODE_LOTSTEP);

   double SLPts=MathAbs(price1-price2);
   //SLPts/=Point;//No idea why *= factor does not work here, but it doesn't
   SLPts = int(SLPts * factor * 10);//Code from Radar. Thanks Radar; much appreciated

   double Exposure=SLPts*TickValue; // Exposure based on 1 full lot

   double AllowedExposure=(FreeMargin*RiskPercent)/100;

   int TotalSteps = ((AllowedExposure / Exposure) / LotStep);
   double LotSize = TotalSteps * LotStep;

   double MinLots = MarketInfo(Symbol(), MODE_MINLOT);
   double MaxLots = MarketInfo(Symbol(), MODE_MAXLOT);

   if(LotSize < MinLots) LotSize = MinLots;
   if(LotSize > MaxLots) LotSize = MaxLots;
   return(LotSize);

}//double CalculateLotSize(double price1, double price1)
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double CalculateStopLoss(int type, double price)
{
   //Returns the stop loss for use in LookForTradingOpps and InsertMissingStopLoss
   double stop;

   if (type == OP_BUY)
   {
      //Regular trades
      if (!PullBackTrade)
      {
         //SL at the bottom of the first candle in the sequence
         if (UseCandleSequenceForSL)
         {
            stop = iLow(Symbol(), TradingTimeFrame, NoOfCandles);
            HiddenStopLoss = stop;
         }//if (UseCandleSequenceForSL)

         if (!CloseEnough(StopLoss, 0) )
         {
            stop = price - (StopLoss / factor);
            HiddenStopLoss = stop;
         }//if (!CloseEnough(StopLoss, 0) )

      }//if (!PullBackTrade)

      //Pullback trades
      if (PullBackTrade)
      {
         stop = NormalizeDouble(price - (PullbackTradeStopLoss / factor), Digits);
         HiddenStopLoss = stop;
      }//if (PullBackTrade)

      if (HiddenPips > 0 && stop > 0) stop = NormalizeDouble(stop - (HiddenPips / factor), Digits);

   }//if (type == OP_BUY)

   if (type == OP_SELL)
   {
      //Regular trades
      if (!PullBackTrade)
      {
         //SL at the top of the first candle in the sequence
         if (UseCandleSequenceForSL)
         {
            stop = iHigh(Symbol(), TradingTimeFrame, NoOfCandles);
            HiddenStopLoss = stop;
         }//if (UseCandleSequenceForSL)

         if (!CloseEnough(StopLoss, 0) )
         {
            stop = price + (StopLoss / factor);
            HiddenStopLoss = stop;
         }//if (!CloseEnough(StopLoss, 0) )
      }//if (!PullBackTrade)

      //Pullback trades
      if (PullBackTrade)
      {
         stop = NormalizeDouble(price + (PullbackTradeStopLoss / factor), Digits);
         HiddenStopLoss = stop;
      }//if (PullBackTrade)

      if (HiddenPips > 0 && stop > 0) stop = NormalizeDouble(stop + (HiddenPips / factor), Digits);

   }//if (type == OP_SELL)

   return(stop);

}//End double CalculateStopLoss(int type)

double CalculateTakeProfit(int type, double price, double stop)
{
   //Returns the stop loss for use in LookForTradingOpps and InsertMissingStopLoss
   double take = 0, pips = 0;

   if (!CloseEnough(RatioOfSlForTP, 0) || !CloseEnough(PercentageOfSlForTP, 0) )
   {
      pips = MathAbs(price - stop);
   }//if (!CloseEnough(RatioOfSlForTP, 0) || !CloseEnough(PercentageOfSlForTP, 0) )

   if (type == OP_BUY)
   {
      //Regular trades
      if (!PullBackTrade)
      {

         //Calculate tp as a ratio of the SL
         if (!CloseEnough(RatioOfSlForTP, 0))
         {
            pips*= RatioOfSlForTP;
            take = NormalizeDouble((price + pips), Digits);
            HiddenTakeProfit = take;
         }//if (!CloseEnough(RatioOfSlForTP, 0))

         //Calculate tp as a percentage of the SL
         if (!CloseEnough(PercentageOfSlForTP, 0))
         {
            pips = (pips * RatioOfSlForTP) / 100;
            take = NormalizeDouble((price + pips), Digits);
            HiddenTakeProfit = take;
         }//if (!CloseEnough(PercentageOfSlForTP, 0))

         if (!CloseEnough(TakeProfit, 0) )
         {
            take = price + (TakeProfit / factor);
            HiddenTakeProfit = take;
         }//if (!CloseEnough(TakeProfit, 0) )

      }//if (!PullBackTrade)

      //Pullback trades
      if (PullBackTrade)
         if (!CloseEnough(PullbackTradeTakeProfit, 0))
         {
            take = NormalizeDouble(Ask + (PullbackTradeTakeProfit / factor), Digits);
            HiddenTakeProfit = take;
         }//if (!CloseEnough(PullbackTradeTakeProfit, 0))

      if (HiddenPips > 0 && take > 0) take = NormalizeDouble(take + (HiddenPips / factor), Digits);

   }//if (type == OP_BUY)

   if (type == OP_SELL)
   {

      //Regular trades
      if (!PullBackTrade)
      {
         //Calculate tp as a ratio of the SL
         if (!CloseEnough(RatioOfSlForTP, 0))
         {
            pips*= RatioOfSlForTP;
            take = NormalizeDouble((price - pips), Digits);
            HiddenTakeProfit = take;
         }//if (!CloseEnough(RatioOfSlForTP, 0))

         //Calculate tp as a percentage of the SL
         if (!CloseEnough(PercentageOfSlForTP, 0))
         {
            pips = (pips * RatioOfSlForTP) / 100;
            take = NormalizeDouble((price - pips), Digits);
            HiddenTakeProfit = take;
         }//if (!CloseEnough(PercentageOfSlForTP, 0))

         if (!CloseEnough(TakeProfit, 0) )
         {
            take = Bid - (TakeProfit / factor);
            HiddenTakeProfit = take;
         }//if (!CloseEnough(TakeProfit, 0) )
      }//if (!PullBackTrade)

      //Pullback trades
      if (PullBackTrade)
         if (!CloseEnough(PullbackTradeTakeProfit, 0))
         {
            take = NormalizeDouble(price - (PullbackTradeTakeProfit / factor), Digits);
            HiddenTakeProfit = take;
         }//if (!CloseEnough(PullbackTradeTakeProfit, 0))

      if (HiddenPips > 0 && !CloseEnough(take, 0) ) take = NormalizeDouble(take - (HiddenPips / factor), Digits);

   }//if (type == OP_SELL)

   return(take);

}//End double CalculateTakeProfit(int type)

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void LookForTradingOpportunities()
{
   RefreshRates();
   double take = 0, stop = 0, price = 0;
   int type;
   string stype;//For the alert
   bool SendTrade = false, result = false;

   double SendLots = Lot;
   //Check filters
   if (!IsTradingAllowed() ) return;

   /////////////////////////////////////////////////////////////////////////////////////

   //Trading decision.
   bool SendLong = false, SendShort = false;

   //Long trade

   //Specific system filters
   if (BuySignal)
      SendLong = true;

   //Usual filters
   if (SendLong)
   {

      if (!TradeLong)
         return;

      if (UseZeljko && !BalancedPair(OP_BUY) ) return;

      if (BuyOpen && Ask >= HighestBuyPrice - (MinDistanceBetweenTrades / factor)) return;
      else if (BuyOpen && Ask >= LowestBuyPrice - (MinDistanceBetweenTrades / factor)) return;

      //Change of market state - explanation at the end of start()
      //if (OldAsk <= some_condition) SendLong = false;
   }//if (SendLong)

   /////////////////////////////////////////////////////////////////////////////////////

   if (!SendLong)
   {
      //Short trade
      //Specific system filters
      if (SellSignal)
         SendShort = true;

      if (SendShort)
      {
         //Usual filters

         if (!TradeShort)
         return;

      if (UseZeljko && !BalancedPair(OP_SELL) ) return;

      if (SellOpen && Bid <= LowestSellPrice + (MinDistanceBetweenTrades / factor)) return;
      else if (SellOpen && Bid <= HighestSellPrice + (MinDistanceBetweenTrades / factor)) return;

      }//if (SendShort)

   }//if (!SendLong)

////////////////////////////////////////////////////////////////////////////////////////

   //Long
   if (SendLong)
   {
      type=OP_BUY;
      stype = " Buy ";
      price = Ask;//Change this to whatever the price needs to be

      if (!SendAlertNotTrade && !BasketTrading)
      {

         stop = CalculateStopLoss(OP_BUY, price);
         take = CalculateTakeProfit(OP_BUY, price, stop);

         //Lot size calculated by risk
         if (!CloseEnough(RiskPercent, 0)) SendLots = CalculateLotSize(price, NormalizeDouble(stop + (HiddenPips / factor), Digits) );

      }//if (!SendAlertNotTrade)

      SendTrade = true;

   }//if (SendLong)

   //Short
   if (SendShort)
   {

      type=OP_SELL;
      stype = " Sell ";
      price = Bid;//Change this to whatever the price needs to be

      if (!SendAlertNotTrade && !BasketTrading)
      {

         stop = CalculateStopLoss(OP_SELL, price);
         take = CalculateTakeProfit(OP_SELL, price, stop);

         //Lot size calculated by risk
         if (!CloseEnough(RiskPercent, 0)) SendLots = CalculateLotSize(price, NormalizeDouble(stop - (HiddenPips / factor), Digits) );

      }//if (!SendAlertNotTrade)

      SendTrade = true;

   }//if (SendShort)

   if (SendTrade)
   {
      if (!SendAlertNotTrade)
      {
         result = SendSingleTrade(Symbol(), type, TradeDetailComment, SendLots, price, stop, take);
         //The latest garbage from the morons at Crapperquotes appears to occasionally break Matt's OR code, so tell the
         //ea not to trade for a while, to give time for the trade receipt to return from the server.
         TimeToStartTrading = TimeCurrent() + PostTradeAttemptWaitSeconds;
         if (result)
         {
            if (TakeSnapshots)
            {
               DisplayUserFeedback();
               TakeChartSnapshot(TicketNo, " open");
            }//if (TakeSnapshots)

            if (EmailTradeNotification) SendMail("Trade sent ", Symbol() + stype + "trade at " + TimeToStr(TimeCurrent(), TIME_DATE|TIME_MINUTES));
            if (AlertPush) AlertNow(WindowExpertName() + " " + Symbol() + " " + stype + " " + DoubleToStr(price, Digits) );
            bool s = BetterOrderSelect(TicketNo, SELECT_BY_TICKET, MODE_TRADES);
            //The latest garbage from the morons at Crapperquotes appears to occasionally break Matt's OR code, so send the
            //ea to sleep for a minute to give time for the trade receipt to return from the server.
            Sleep(60000);
         }//if (result)
      }//if (!SendAlertNotTrade)

      if (SendAlertNotTrade && !AlertSent)
      {
         Alert(WindowExpertName(), " ", Symbol(), " ", stype, "trade has triggered. ",  TimeToStr(TimeLocal(), TIME_DATE|TIME_MINUTES|TIME_SECONDS) );
         SendMail("Trade alert. ", Symbol() + " " + stype + " trade has triggered. " +  TimeToStr(TimeLocal(), TIME_DATE|TIME_MINUTES|TIME_SECONDS ));
         if (AlertPush) AlertNow(WindowExpertName() + " " + Symbol() + " " + stype + " " + DoubleToStr(price, Digits) );
         AlertSent=true;
       }//if (SendAlertNotTrade && !AlertSent)
   }//if (SendTrade)

   //Actions when trade send succeeds
   if (SendTrade && result)
   {
      if (!SendAlertNotTrade && !CloseEnough(HiddenPips, 0) ) ReplaceMissingSlTpLines();
   }//if (result)

   //Actions when trade send fails
   if (SendTrade && !result)
   {
      OldBarsTime = 0;
   }//if (!result)

}//void LookForTradingOpportunities()
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+

void AlertNow(string sAlertMsg)
{

   if(AlertPush)
   {
      if(IsTesting()) Print("Message to Push: ",TimeToStr(Time[0],TIME_DATE|TIME_SECONDS)+" "+sAlertMsg);
      SendNotification(StringConcatenate(TimeToStr(Time[0],TIME_DATE|TIME_SECONDS)," "+sAlertMsg));
   }//if (AlertPush)
   return;
}//End void AlertNow(string sAlertMsg)

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CloseOrder(int ticket)
{
   while(IsTradeContextBusy()) Sleep(100);
   bool orderselect=BetterOrderSelect(ticket,SELECT_BY_TICKET,MODE_TRADES);
   if (!orderselect) return(false);

   bool result = OrderClose(ticket, OrderLots(), OrderClosePrice(), 1000, clrBlue);

   //Actions when trade send succeeds
   if (result)
   {
      if (TakeSnapshots)
      {
         DisplayUserFeedback();
         TakeChartSnapshot(TicketNo, " close");
      }//if (TakeSnapshots)

      return(true);
   }//if (result)

   //Actions when trade send fails
   if (!result)
   {
      ReportError(" CloseOrder()", ocm);
      return(false);
   }//if (!result)

   return(0);
}//End bool CloseOrder(ticket)

////////////////////////////////////////////////////////////////////////////////////////
//Indicator module

void CheckForSpreadWidening()
{
   if (CloseEnough(AverageSpread, 0)) return;
   //Detect a dramatic widening of the spread and pause the ea until this passes
   double TargetSpread = AverageSpread * MultiplierToDetectStopHunt;
   double spread = (Ask - Bid) * factor;

   if (spread >= TargetSpread)
   {
      if (OpenTrades == 0) Comment(Gap + "PAUSED DURING A MASSIVE SPREAD EVENT");
      if (OpenTrades > 0) Comment(Gap + "PAUSED DURING A MASSIVE SPREAD EVENT. STILL MONITORING TRADES.");
      while (spread >= TargetSpread)
      {
         RefreshRates();
         spread = (Ask - Bid) * factor;

         CountOpenTrades();
         //Safety feature. Sometimes an unexpected concatenation of inputs choice and logic error can cause rapid opening-closing of trades. Detect a closed trade and check that is was not a rogue.
         if (OldOpenTrades != OpenTrades)
         {
            if (IsClosedTradeRogue() )
            {
               RobotSuspended = true;
               return;
            }//if (IsClosedTradeRogue() )
         }//if (OldOpenTrades != OpenTrades)
         if (ForceTradeClosure) return;//Emergency measure to force a retry at the next tick

         OldOpenTrades = OpenTrades;

         Sleep(1000);

      }//while (spread >= TargetSpread)
   }//if (spread >= TargetSpread)
}//End void CheckForSpreadWidening()

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CalculateDailyResult()
{
   //Calculate the no of winners and losers from today's trading. These are held in the history tab.

   LossTrades = 0;
   WinTrades = 0;
   OverallProfit = 0;


   for (int cc = 0; cc <= OrdersHistoryTotal(); cc++)
   {
      if (!BetterOrderSelect(cc, SELECT_BY_POS, MODE_HISTORY) ) continue;
      if (OrderSymbol() != Symbol() ) continue;
      if (OrderMagicNumber() != MagicNumber) continue;
      if (OrderCloseTime() < iTime(Symbol(), PERIOD_D1, 0) ) continue;

      OverallProfit+= (OrderProfit() + OrderSwap() + OrderCommission() );
      if (OrderProfit() > 0) WinTrades++;
      if (OrderProfit() < 0) LossTrades++;
   }//for (int cc = 0; cc <= tot -1; cc++)



}//End void CalculateDailyResult()

//+------------------------------------------------------------------+
//| GetSlope()                                                       |
//+------------------------------------------------------------------+
void GetAverageSpread()
{

//   ************************* added for OBJ_LABEL
   DisplayCount = 1;
   removeAllObjects();
//   *************************

   static double SpreadTotal=0;
   AverageSpread=0;

   //Add spread to total and keep track of the ticks
   double Spread=(Ask-Bid)*factor;
   SpreadTotal+=Spread;
   CountedTicks++;

   //All ticks counted?
   if(CountedTicks>=TicksToCount)
   {
      AverageSpread=NormalizeDouble(SpreadTotal/TicksToCount,1);
      //Save the average for restarts.
      GlobalVariableSet(SpreadGvName,AverageSpread);
      RunInSpreadDetectionMode=false;
   }//if (CountedTicks >= TicksToCount)


}//void GetAverageSpread()
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+

double GetSuperSlope(string symbol, int tf, int maperiod, int atrperiod, int pShift )
{
   double dblTma, dblPrev;
   int shiftWithoutSunday = pShift;

   double atr = iATR( symbol, tf, atrperiod, shiftWithoutSunday + 10 ) / 10;
   double result = 0.0;
   if ( atr != 0 )
   {
      dblTma = iMA( symbol, tf, maperiod, 0, MODE_LWMA, PRICE_CLOSE, shiftWithoutSunday );
      dblPrev = ( iMA( symbol, tf, maperiod, 0, MODE_LWMA, PRICE_CLOSE, shiftWithoutSunday + 1 ) * 231 + iClose( symbol, tf, shiftWithoutSunday ) * 20 ) / 251;

      result = ( dblTma - dblPrev ) / atr;
   }

   return ( result );

}//GetSuperSlope(}

string GetLatestHgiSignal(string symbol, int tf)
{

   //Returns the latest signal on the relevant time frame passed via tf

   string HgiSignal = hginoarrow;

   for (int cc = 1; cc <= iBars(symbol, tf); cc++)
   {


      SIGNAL signal = 0;
      SLOPE slope = 0;

      signal = getHGISignal(symbol, tf, cc);//This library function looks for arrows.
      slope  = getHGISlope (symbol, tf, cc);//This library function looks for wavy lines.

      if (signal==TRENDUP)
      {
         if (TradeTrendArrows)
         HgiSignal = hgiuparrowtradable;
      }
      else
      if (signal==TRENDDN)
      {
         if (TradeTrendArrows)
            HgiSignal = hgidownarrowtradable;
      }
      else
      if (slope==TRENDBELOW)
      {
         if (TradeBlueWavyLines)
            HgiSignal = hgibluewavylong;
      }
      else
      if (slope==TRENDABOVE)
      {
         if (TradeBlueWavyLines)
            HgiSignal = hgibluewavyshort;
      }
      else
      if (YellowRangeLinePreventsTrading)
      {
         if (slope==RANGEABOVE || slope == RANGEBELOW)
         {
            //No need to discriminate between the market and the yellow lines - a range
            //is a range and we are closing all trades on a range or ranging prevents trading.
            HgiSignal = hgiyellowrangewavey;
         }//if (slope==RANGEABOVE || slope == RANGEBELOW)

      }//if (HgiCloseOnYellowWavy)

      /*else
      if (signal==RADUP)
      {
         if (RadTradingAllowed)
         HgiSignal = hgiuparrowtradable;
      }
      else
      if (signal==RADDN)
      {
         if (RadTradingAllowed)
            HgiSignal = hgiuparrowtradable;
      */

      //Break our of the loop when a signal is found
      if (HgiSignal != hginoarrow)
         break;

   }//for (int cc = 1; cc <= iBars(symbol, tf; cc++)

   return(HgiSignal);

}//End string GetLatestHgiSignal(srting symbol, int tf)

int GetNextTimeFrame(int tf)
{
   //Finds and returns the next time frame up.

   int NewTf = 0;
   switch(tf)
   {
      case PERIOD_M1:
         NewTf = PERIOD_M5;
         return(NewTf);

      case PERIOD_M5:
         NewTf = PERIOD_M15;
         return(NewTf);

      case PERIOD_M15:
         NewTf = PERIOD_M30;
         return(NewTf);

      case PERIOD_M30:
         NewTf = PERIOD_H1;
         return(NewTf);

      case PERIOD_H1:
         NewTf = PERIOD_H4;
         return(NewTf);

      case PERIOD_H4:
         NewTf = PERIOD_D1;
         return(NewTf);

      case PERIOD_D1:
         NewTf = PERIOD_W1;
         return(NewTf);

      case PERIOD_W1:
         NewTf = PERIOD_MN1;
         return(NewTf);

      case PERIOD_MN1:
         return(0);


   }//switch(tf)

   //In case something goes wrong
   return(0);

}//int GetNextTimeFrame(int tf)

double GetNextSupport(string symbol, int tf)
{
   //This is an implementation of Andrew Sumner's Support/Resistance Indicator
   //To be found at http://www.stevehopwoodforex.com/phpBB3/viewtopic.php?f=27&t=514
   //SSSR_UpdateZones(true, Symbol(), SRTimeFrame);

   //Finding the support zones closest to the ask/bid price
   double zone = NormalizeDouble(SSSR_FindZoneV2(SSSR_DN, true, Bid, sup_hi, sup_lo, sup_strength), Digits);

   //We need to deal with the situation where there is no support on the passed time frame.
   //There is probably a more efficient way of doing this, but this will do for now.
   if (CloseEnough(zone, 0))
   {
      //Find the next time frame up
      int NewTf = GetNextTimeFrame(tf);

      //Loop around the time frames looking for a support zone
      while (NewTf <= PERIOD_MN1)
      {
         SSSR_UpdateZones(true, Symbol(), NewTf);
         zone = NormalizeDouble(SSSR_FindZoneV2(SSSR_DN, true, Bid, sup_hi, sup_lo, sup_strength), Digits);
         if (!CloseEnough(zone, 0) )
            return(zone);

         //Are we at an all time low?
         if (NewTf == PERIOD_MN1)
            return(0);

         //No, so find the next time frame up
         NewTf = GetNextTimeFrame(NewTf);

      }//while (NewTf <= PERIOD_MN1)
   }//if (CloseEnough(zone, 0))

   return(zone);

}//End double GetNextSupport(string symbol, int tf)

double GetNextResistance(string symbol, int tf)
{
   //This is an implementation of Andrew Sumner's Support/Resistance Indicator
   //To be found at http://www.stevehopwoodforex.com/phpBB3/viewtopic.php?f=27&t=514
   //SSSR_UpdateZones(true, Symbol(), SRTimeFrame);

   //Finding the support zones closest to the ask/bid price
   double zone = NormalizeDouble(SSSR_FindZoneV2(SSSR_UP, true, Bid, res_hi, res_lo, res_strength), Digits);

   //We need to deal with the situation where there is no support on the passed time frame.
   //There is probably a more efficient way of doing this, but this will do for now.
   if (CloseEnough(zone, 0))
   {
      //Find the next time frame up
      int NewTf = GetNextTimeFrame(tf);

      //Loop around the time frames looking for a support zone
      while (NewTf <= PERIOD_MN1)
      {
         SSSR_UpdateZones(true, Symbol(), NewTf);
         zone = NormalizeDouble(SSSR_FindZoneV2(SSSR_UP, true, Bid, res_hi, res_lo, res_strength), Digits);
         if (!CloseEnough(zone, 0) )
            return(zone);

         //Are we at an all time low?
         if (NewTf == PERIOD_MN1)
            return(0);

         //No, so find the next time frame up
         NewTf = GetNextTimeFrame(NewTf);

      }//while (NewTf <= PERIOD_MN1)
   }//if (CloseEnough(zone, 0))

   return(zone);

}//End double GetNextResistance(string symbol, int tf)


void CalculateSsValues()
{
   if (UseHtfSS)
   {
      static datetime OldHtfSsTimeFrame = 0;
      if (OldHtfSsTimeFrame != iTime(Symbol(),SSHtfReadCycle, 0))
      {
         OldHtfSsTimeFrame = iTime(Symbol(), SSHtfReadCycle, 0);

         //Read SuperSlope at the open of each new trading time frame candle
         HtfSsVal = GetSuperSlope(Symbol(), HtfSsTimeFrame,HtfSsSlopeMAPeriod,HtfSsSlopeATRPeriod,0);

         //Changed by tomele. Many thanks Thomas.
         //Set the colours
         HtfSsStatus = white;

         if (HtfSsVal > 0)  //buy
            if (HtfSsVal - HtfSsDifferenceThreshold/2 > 0) //blue
               if (HtfSsVal >= HtfMinimumBuyValue)
                  HtfSsStatus = blue;

         if (HtfSsVal < 0)  //sell
            if (HtfSsVal + HtfSsDifferenceThreshold/2 < 0) //red
               if (HtfSsVal <= HtfMinimumSellValue)
                  HtfSsStatus = red;

         // TDesk code
         if (HtfSsStatus==white)    PublishTDeskSignal("SS-3",HtfSsTimeFrame,Symbol(),FLAT);
         else if(HtfSsStatus==blue) PublishTDeskSignal("SS-3",HtfSsTimeFrame,Symbol(),LONG);
         else if(HtfSsStatus==red)  PublishTDeskSignal("SS-3",HtfSsTimeFrame,Symbol(),SHORT);

      }//if (UseHtfSS)
   }

   if (UseMtfSS)
   {
      static datetime OldMtfSsTimeFrame = 0;
      if (OldMtfSsTimeFrame != iTime(Symbol(), SSMtfReadCycle, 0))
      {
         OldMtfSsTimeFrame = iTime(Symbol(), SSMtfReadCycle, 0);
         //Read SuperSlope at the open of each new trading time frame candle
         MtfSsVal = GetSuperSlope(Symbol(), MtfSsTimeFrame,MtfSsSlopeMAPeriod,MtfSsSlopeATRPeriod,0);

         //Changed by tomele. Many thanks Thomas.
         //Set the colours
         MtfSsStatus = white;

         if (MtfSsVal > 0)  //buy
            if (MtfSsVal - MtfSsDifferenceThreshold/2 > 0) //blue
               if (MtfSsVal >= MtfMinimumBuyValue)
                  MtfSsStatus = blue;

         if (MtfSsVal < 0)  //sell
            if (MtfSsVal + MtfSsDifferenceThreshold/2 < 0) //red
               if (MtfSsVal <= MtfMinimumSellValue)
                  MtfSsStatus = red;

         // TDesk code
         if (MtfSsStatus==white)    PublishTDeskSignal("SS-2",MtfSsTimeFrame,Symbol(),FLAT);
         else if(MtfSsStatus==blue) PublishTDeskSignal("SS-2",MtfSsTimeFrame,Symbol(),LONG);
         else if(MtfSsStatus==red)  PublishTDeskSignal("SS-2",MtfSsTimeFrame,Symbol(),SHORT);

      }//if (UseMtfSS)
   }

   if (UseLtfSS)
   {
      static datetime OldLtfSsTimeFrame = 0;
      if (OldLtfSsTimeFrame != iTime(Symbol(), SSLtfReadCycle, 0))
      {
         OldLtfSsTimeFrame = iTime(Symbol(), SSLtfReadCycle, 0);
         //Read SuperSlope at the open of each new trading time frame candle
         LtfSsVal = GetSuperSlope(Symbol(), LtfSsTimeFrame,LtfSsSlopeMAPeriod,LtfSsSlopeATRPeriod,0);

         //Changed by tomele. Many thanks Thomas.
         //Set the colours
         LtfSsStatus = white;

         if (LtfSsVal > 0)  //buy
            if (LtfSsVal - LtfSsDifferenceThreshold/2 > 0) //blue
               if (LtfSsVal >= HtfMinimumBuyValue)
                  LtfSsStatus = blue;

         if (LtfSsVal < 0)  //sell
            if (LtfSsVal + LtfSsDifferenceThreshold/2 < 0) //red
               if (LtfSsVal <= LtfMinimumSellValue)
                  LtfSsStatus = red;

         // TDesk code
         if (LtfSsStatus==white)    PublishTDeskSignal("SS-1",LtfSsTimeFrame,Symbol(),FLAT);
         else if(LtfSsStatus==blue) PublishTDeskSignal("SS-1",LtfSsTimeFrame,Symbol(),LONG);
         else if(LtfSsStatus==red)  PublishTDeskSignal("SS-1",LtfSsTimeFrame,Symbol(),SHORT);

      }//if (UseLtfSS)
   }

   //Group the SS colours to detect the overall direction for the trading decision.
   AllColours = mixed;
   if (!UseHtfSS || HtfSsStatus == blue)
      if (!UseMtfSS || MtfSsStatus == blue )
         if (!UseLtfSS || LtfSsStatus == blue )
            AllColours = blue;

   if (!UseHtfSS || HtfSsStatus == red )
      if (!UseMtfSS || MtfSsStatus == red)
         if (!UseLtfSS || LtfSsStatus == red)
            AllColours = red;

}//End void CalculateSsValues()

void CalculateHGIValues()
{
   //Htf
   if (UseHtfHGI)
   {
      static datetime OldHtfHGITimeFrame = 0;
      if (OldHtfHGITimeFrame != iTime(Symbol(), HGIHtfReadCycle, 0) )
      {
         OldHtfHGITimeFrame = iTime(Symbol(), HGIHtfReadCycle, 0);
         HtfHgiStatus = GetLatestHgiSignal(Symbol(), HtfTimeFrame);

         // TDesk code
         if (HtfHgiStatus==hgiuparrowtradable || HtfHgiStatus == hgibluewavylong) PublishTDeskSignal("HGI-1",HtfTimeFrame,Symbol(),LONG);
         else if(HtfHgiStatus==hgidownarrowtradable || HtfHgiStatus == hgibluewavyshort) PublishTDeskSignal("HGI-1",HtfTimeFrame,Symbol(),SHORT);
         else if(HtfHgiStatus==hgiyellowrangewavey) PublishTDeskSignal("HGI-1",HtfTimeFrame,Symbol(),FLAT);

      }//if (OldHtfTimeFrame != iTime(Symbol(), HtfTimeFrame, 0) )
   }

   //Mtf
   if (UseMtfHGI)
   {
      static datetime OldMtfHGITimeFrame = 0;
      if (OldMtfHGITimeFrame != iTime(Symbol(), HGIMtfReadCycle, 0) )
      {
         OldMtfHGITimeFrame = iTime(Symbol(), HGIMtfReadCycle, 0);
         MtfHgiStatus = GetLatestHgiSignal(Symbol(), MtfTimeFrame);

         // TDesk code
         if (MtfHgiStatus==hgiuparrowtradable || MtfHgiStatus == hgibluewavylong) PublishTDeskSignal("HGI-2",MtfTimeFrame,Symbol(),LONG);
         else if(MtfHgiStatus==hgidownarrowtradable || MtfHgiStatus == hgibluewavyshort) PublishTDeskSignal("HGI-2",MtfTimeFrame,Symbol(),SHORT);
         else if(MtfHgiStatus==hgiyellowrangewavey) PublishTDeskSignal("HGI-2",MtfTimeFrame,Symbol(),FLAT);

      }//if (OldMtfTimeFrame != iTime(Symbol(), MtfTimeFrame, 0) )
   }

   //Ltf
   if (UseLtfHGI)
   {
      static datetime OldLtfHGITimeFrame = 0;
      if (OldLtfHGITimeFrame != iTime(Symbol(), HGILtfReadCycle, 0) )
      {
         OldLtfHGITimeFrame = iTime(Symbol(), HGILtfReadCycle, 0);
         LtfHgiStatus = GetLatestHgiSignal(Symbol(), LtfTimeFrame);

         // TDesk code
         if (LtfHgiStatus==hgiuparrowtradable || LtfHgiStatus == hgibluewavylong) PublishTDeskSignal("HGI-3",LtfTimeFrame,Symbol(),LONG);
         else if(LtfHgiStatus==hgidownarrowtradable || LtfHgiStatus == hgibluewavyshort) PublishTDeskSignal("HGI-3",LtfTimeFrame,Symbol(),SHORT);
         else if(LtfHgiStatus==hgiyellowrangewavey) PublishTDeskSignal("HGI-3",LtfTimeFrame,Symbol(),FLAT);

      }//if (OldLtfTimeFrame != iTime(Symbol(), LtfTimeFrame, 0) )
   }

   //Define the status of AllSignals
   AllSignals = mixed;
   //Up signals
   if (HtfHgiStatus == hgiuparrowtradable || HtfHgiStatus == hgibluewavylong)
      if (MtfHgiStatus == hgiuparrowtradable || MtfHgiStatus == hgibluewavylong)
         if (LtfHgiStatus == hgiuparrowtradable || LtfHgiStatus == hgibluewavylong)
            AllSignals = up;

   //Down signals
   if (HtfHgiStatus == hgidownarrowtradable || HtfHgiStatus == hgibluewavyshort)
      if (MtfHgiStatus == hgidownarrowtradable || MtfHgiStatus == hgibluewavyshort)
         if (LtfHgiStatus == hgidownarrowtradable || LtfHgiStatus == hgibluewavyshort)
            AllSignals = down;
}

void CalculateCandleDirection()
{
   //Regular trades
   //Read the direction of the previous NoOfCandles bars and calculate the direction
   ups = 0;
   downs = 0;

   OverallCandleDirection = mixed;//Default
   OverallPullbackCandleDirection = mixed;//Default
   PullBackTrade = false;//For the sl/tp

   for (int cc = 1; cc <= NoOfCandlesToMeasurePullback; cc++)
   {
      //Read the open and close prices
      double copen = iOpen(Symbol(), TradingTimeFrame, cc);
      double cclose = iClose(Symbol(), TradingTimeFrame, cc);

      //Define the candle direction.
      PreviousCandleDirection[cc] = mixed;//Default
      //Up candle
      if (cclose > copen)
      {
         PreviousCandleDirection[cc] = up;
         ups++;
      }//if (cclose > copen)

      //Down candle
      if (cclose < copen)
      {
         PreviousCandleDirection[cc] = down;
         downs++;
      }//if (cclose < copen)

   }//for (cc = 1; cc < NoOfCandlesToMeasurePullback; cc++)

   //Set the status of the candle direction
   OverallCandleDirection = up;
   for (cc = 1; cc <= NoOfCandles; cc++)
   {
      if (PreviousCandleDirection[cc] == down)
      {
         OverallCandleDirection = mixed;
         PublishTDeskSignal("CD",TradingTimeFrame,Symbol(),FLAT);
         break;
      }//if (PreviousCandleDirection[cc] == down)

   }//for (cc = 1; cc <= NoOfCandles; cc++)

   if (OverallCandleDirection == mixed)
   {
      OverallCandleDirection = down;
      for (cc = 1; cc <= NoOfCandles; cc++)
      {
         if (PreviousCandleDirection[cc] == up)
         {
            OverallCandleDirection = mixed;
            PublishTDeskSignal("CD",TradingTimeFrame,Symbol(),FLAT);
            break;
         }//if (PreviousCandleDirection[cc] == up)
      }//for (cc = 1; cc <= NoOfCandles; cc++)

   }//if (OverallCandleDirection == mixed)

   if (OverallCandleDirection == up) PublishTDeskSignal("CD",TradingTimeFrame,Symbol(),LONG);
   else if (OverallCandleDirection == down) PublishTDeskSignal("CD",TradingTimeFrame,Symbol(),SHORT);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ReadIndicatorValues()
{
   //Declare a datetime variable to force reading Indiucators only at the open of a new candle.
   static datetime OldCcaReadTime = 0;

   //Accommodate every tick mode
   if (EveryTickMode)
      OldCcaReadTime = 0;

   CalculateHGIValues();
   CalculateSsValues();

   if (OldCcaReadTime != iTime(Symbol(), LookForNewTradeCycle, 0) )
   {
      OldCcaReadTime = iTime(Symbol(), LookForNewTradeCycle, 0);

      TradeDetailComment = TradeComment;
      CountOpenTrades();
      CalculateCandleDirection();

      double RSI1 = iRSI(Symbol(),TradingTimeFrame,14,0,1);
      double Stoch1 = iStochastic(Symbol(),TradingTimeFrame,5,3,3,0,0,0,1);

      //Do we have a trade signal
      BuySignal = false;
      SellSignal = false;

      //Code to compare all the indi values and generate a signal if they all pass
      //Open new trades inside support or resistance zones allowed
      if (OverallCandleDirection == up && CashUpl <= 0)
         if (AllSignals == up || AllColours == blue)
            if (!OnlyTradeThePullback)
            {
               BuySignal = true;
               if (AllSignals == up) TradeDetailComment += " - HGI";
               else if (AllColours == blue) TradeDetailComment += " - SS";
            }

      if (OverallCandleDirection == down && CashUpl <= 0)
         if (AllSignals == down || AllColours == red)
            if (!OnlyTradeThePullback)
            {
               SellSignal = true;
               if (AllSignals == down) TradeDetailComment += " - HGI";
               else if (AllColours == red) TradeDetailComment += " - SS";
            }

      //Trading the pullback
      if (!BuySignal)
         if (!SellSignal)
            if (TradeThePullback || OnlyTradeThePullback)
            {
               //Long trades only
               if (AllSignals == up || AllColours == blue)
                  if (downs == NoOfCandlesToMeasurePullback && CashUpl <= 0)
                  {
                     BuySignal = true;
                     PullBackTrade = true;
                     OverallPullbackCandleDirection = down;
                     if (AllSignals == up) TradeDetailComment += " - HGI";
                     else if (AllColours == blue) TradeDetailComment += " - SS";
                  }//if (downs = NoOfCandlesToMeasurePullback)

               //Short trades only
               if (AllSignals == down || AllColours == red)
                  if (ups == NoOfCandlesToMeasurePullback && CashUpl <= 0)
                  {
                     SellSignal = true;
                     PullBackTrade = true;
                     OverallPullbackCandleDirection = up;
                     if (AllSignals == down) TradeDetailComment += " - HGI";
                     else if (AllColours == red) TradeDetailComment += " - SS";
                  }//if (ups == NoOfCandlesToMeasurePullback)

            }//if (TradeThePullback || OnlyTradeThePullback)

      //Test for being inside a SR zone.
      if (UseSuppRes)
      {
         //////////////////////////////////////////////////////////////
         //    Reading the SS_SupportResistance Indi                 //
         //////////////////////////////////////////////////////////////
         //This is an implementation of Andrew Sumner's Support/Resistance Indicator
         //To be found at http://www.stevehopwoodforex.com/phpBB3/viewtopic.php?f=27&t=514
         SSSR_UpdateZones(true, Symbol(), SRTimeFrame);

         //Finding the support & resistance zones closest to the ask/bid price
         res_zone = GetNextResistance(Symbol(), SRTimeFrame);
         sup_zone = GetNextSupport(Symbol(), SRTimeFrame);

         //Test for being inside a zone.
         bool InsideSupport = false;
         bool InsideResistance = false;
         bool InsideZone = false;

         //Resistance zone cancels buys.
         if (Bid <= res_hi && Bid >= res_lo-(SRBuffer/factor))
            InsideResistance = true;
         //Support zone cancels sells
         else if (Bid <= sup_hi+(SRBuffer/factor) && Bid >= sup_lo)
            InsideSupport = true;

         //Test the Ask
         //Resistance zone cancels buys.
         if (Ask <= res_hi && Ask >= res_lo-(SRBuffer/factor))
            InsideResistance = true;
         //Support zone cancels sells
         else if (Ask <= sup_hi+(SRBuffer/factor) && Ask >= sup_lo)
            InsideSupport = true;

         if (InsideSupport || InsideResistance)
            InsideZone = true;

         if (BuySignal || SellSignal)
         {
            if (DontOpenTradesInsideSRZones && !OpenSomeTradesInsideSRZones)
               if (InsideZone)
               {
                  BuySignal = false;
                  SellSignal = false;
               }//if (InsideZone)

            if (OpenSomeTradesInsideSRZones)
            {
                if (BuySignal && InsideResistance)
                  //if (Bid <= res_hi && Bid >= res_lo) // && OpenTrades == 0)
                     BuySignal = false;

                if (SellSignal && InsideSupport)
                  //if (Ask <= sup_hi && Ask >= sup_lo) // && OpenTrades == 0)
                     SellSignal = false;

            }//if (OpenSomeTradesInsideSRZones)

            //Test for being at an all time hi / lo
            if (BuySignal)
               if (CloseEnough(res_hi, 0) || CloseEnough(res_lo, 0) || CloseEnough(res_zone, 0))
                  BuySignal = false;

            if (SellSignal)
               if (CloseEnough(sup_hi, 0) || CloseEnough(sup_lo, 0) || CloseEnough(sup_zone, 0))
                  SellSignal = false;

         }//BuySignal/SellSignal
      }//UseSuppRes

      if (BuySignal && RSI1 >= 70) // || Stoch1 >= 80)) // || StochH1 >= 70)) // || Stoch4h >= 80))
        BuySignal = false;

      if (SellSignal && RSI1 <= 30) // || Stoch1 <= 20)) // || StochH1 <= 30)) // || Stoch4h <= 20))
        SellSignal = false;

      //Close trades on an opposite direction signal
      BuyCloseSignal = false;
      SellCloseSignal = false;

      //Opposite direction trade signal
      if (BuySignal)
         if (CloseTradesOnOppositeSignal)
            SellCloseSignal = true;

      if (SellSignal)
         if (CloseTradesOnOppositeSignal)
            BuyCloseSignal = true;

      //Close on Opposite HGI Signal
      if (!BuyCloseSignal)
         if (!SellCloseSignal)
            if (HgiCloseOnOppositeSignal)
            {
               if (AllSignals == up)
                  SellCloseSignal = true;

               if (AllSignals == down)
                  BuyCloseSignal = true;
            }//if (HgiCloseOnOppositeSignal)

      //Individual time frame HGI/SS
      if (!BuyCloseSignal)
         if (!SellCloseSignal)
         {
            if (!BuyCloseSignal)
               if (BuyOpen)
               {
                 if (HtfCloseOnOppositeSignal || HtfSSCloseOnOppositeSignal)
                   if (HtfCloseOnOppositeSignal && (HtfHgiStatus == hgidownarrowtradable || HtfHgiStatus == hgibluewavyshort))
                      BuyCloseSignal = true;
                   else if (HtfSSCloseOnOppositeSignal && HtfSsStatus == red)
                      BuyCloseSignal = true;

                 if (!BuyCloseSignal)
                  if (HtfCloseOnYellowWavey)
                     if (HtfHgiStatus == hgiyellowrangewavey)
                        BuyCloseSignal = true;

                 if (!BuyCloseSignal)
                  if (MtfCloseOnOppositeSignal || MtfSSCloseOnOppositeSignal)
                     if (MtfCloseOnOppositeSignal && (MtfHgiStatus == hgidownarrowtradable || MtfHgiStatus == hgibluewavyshort))
                        BuyCloseSignal = true;
                     else if (MtfSSCloseOnOppositeSignal && MtfSsStatus == red)
                        BuyCloseSignal = true;

                 if (!BuyCloseSignal)
                  if (MtfCloseOnYellowWavey)
                     if (MtfHgiStatus == hgiyellowrangewavey)
                        BuyCloseSignal = true;

                 if (!BuyCloseSignal)
                  if (LtfCloseOnOppositeSignal || LtfSSCloseOnOppositeSignal)
                     if (LtfCloseOnOppositeSignal && (LtfHgiStatus == hgidownarrowtradable || LtfHgiStatus == hgibluewavyshort))
                        BuyCloseSignal = true;
                     else if (LtfSSCloseOnOppositeSignal && LtfSsStatus == red)
                        BuyCloseSignal = true;

                 if (!BuyCloseSignal)
                  if (LtfCloseOnYellowWavey)
                     if (LtfHgiStatus == hgiyellowrangewavey)
                        BuyCloseSignal = true;
               }//if (BuyOpen)

            if (!SellCloseSignal)
               if (SellOpen)
               {
                 if (HtfCloseOnOppositeSignal || HtfSSCloseOnOppositeSignal)
                   if (HtfCloseOnOppositeSignal && (HtfHgiStatus == hgiuparrowtradable || HtfHgiStatus == hgibluewavylong))
                      SellCloseSignal = true;
                   else if (HtfSSCloseOnOppositeSignal && HtfSsStatus == blue)
                      SellCloseSignal = true;

                 if (!SellCloseSignal)
                  if (HtfCloseOnYellowWavey)
                     if (HtfHgiStatus == hgiyellowrangewavey)
                        SellCloseSignal = true;

                 if (!SellCloseSignal)
                  if (MtfCloseOnOppositeSignal || MtfSSCloseOnOppositeSignal)
                     if (MtfCloseOnOppositeSignal && (MtfHgiStatus == hgiuparrowtradable || MtfHgiStatus == hgibluewavylong))
                        SellCloseSignal = true;
                     else if (MtfSSCloseOnOppositeSignal && MtfSsStatus == blue)
                        SellCloseSignal = true;

                 if (!SellCloseSignal)
                  if (MtfCloseOnYellowWavey)
                     if (MtfHgiStatus == hgiyellowrangewavey)
                        SellCloseSignal = true;

                 if (!SellCloseSignal)
                  if (LtfCloseOnOppositeSignal || LtfSSCloseOnOppositeSignal)
                     if (LtfCloseOnOppositeSignal && (LtfHgiStatus == hgiuparrowtradable || LtfHgiStatus == hgibluewavylong))
                        SellCloseSignal = true;
                     else if (LtfSSCloseOnOppositeSignal && LtfSsStatus == blue)
                        SellCloseSignal = true;

                 if (!SellCloseSignal)
                  if (LtfCloseOnYellowWavey)
                     if (LtfHgiStatus == hgiyellowrangewavey)
                        SellCloseSignal = true;

               }//if (SellOpen)
         }//if (!SellCloseSignal)

         if (!BuyCloseSignal)
           if (!SellCloseSignal)
            if (CloseTradesOnSsReversal)
            {
               if (AllColours == blue)
                  SellCloseSignal = true;

               if (AllColours == red)
                  BuyCloseSignal = true;

            }//if (CloseTradesOnSsReversa

   }//if (OldCcaReadTime != iTime(Symbol(), TradingTimeFrame, 0) )

   //SR closure
   if (UseSuppRes)
   {
      //////////////////////////////////////////////////////////////
      //    BuyClose on SS_SupportResistance Indi dependencies    //
      //////////////////////////////////////////////////////////////
      //This function is called before CountOpenTrades(), so we need to know if trades are open to
      //avoid multiple alerts.
      CountOpenTrades();

      double sup_hi_with_spread = sup_hi+(Ask-Bid);
      double sup_lo_with_spread = sup_lo+(Ask-Bid);
      double res_hi_with_spread = res_hi-(Ask-Bid);
      double res_lo_with_spread = res_lo-(Ask-Bid);

      if (BuyOpen)
      {
         if (!BuyCloseSignal)
            if (UseResHighforBuyTP)
                if (!CloseEnough(res_hi, 0) )
                  if (Bid >= res_hi_with_spread)
                  {
                     BuyCloseSignal = true;
                     if (ShowAlertWhenTradeCloses)
                        Alert(Symbol(), " market is within a resistance zone. All buy trades should have closed at TP.");
                  }//if (Bid >= NormalizeDouble(res_hi, Digits))

         if (!BuyCloseSignal)
            if (UseResLowforBuyTP)
               if (!CloseEnough(res_lo, 0) )
                  if (Bid >= res_lo_with_spread)
                  {
                     BuyCloseSignal = true;
                     if (ShowAlertWhenTradeCloses)
                        Alert(Symbol(), " market is within a resistance zone. All buy trades should have closed at TP.");
                  }//if (Bid >= NormalizeDouble(res_lo, Digits))

         if (!BuyCloseSignal)
            if (UseSupLowforBuySL)
               if (!CloseEnough(sup_lo, 0) )
                 if (Bid <= sup_lo_with_spread)
                 {
                     BuyCloseSignal = true;
                     if (ShowAlertWhenTradeCloses)
                        Alert(Symbol(), " market is within a resistance zone. All buy trades should have closed at SL.");
                 }//if (Bid <= NormalizeDouble(sup_lo, Digits))

         if (!BuyCloseSignal)
            if (UseSupHighforBuySL)
               if (!CloseEnough(sup_hi, 0) )
                  if (Bid <= sup_hi_with_spread)
                  {
                     BuyCloseSignal = true;
                     if (ShowAlertWhenTradeCloses)
                        Alert(Symbol(), " market is within a resistance zone. All buy trades should have closed at SL.");
                  }//if (Bid <= NormalizeDouble(sup_hi, Digits))

      }//if (BuyOpen)

      ///////////////////////////////////////////////////////////
      //  SellClose on SS_SupportResistance Indi dependencies  //
      ///////////////////////////////////////////////////////////
      if (SellOpen)
      {
         if (!SellCloseSignal)
            if (UseSupHighforSellTP)
               if (!CloseEnough(sup_hi, 0) )
                  if (Ask <= sup_hi_with_spread)
                  {
                     SellCloseSignal = true;
                     if (ShowAlertWhenTradeCloses)
                        Alert(Symbol(), " market is within a support zone. All sell trades should have closed at TP.");
                  }//if (Ask <= NormalizeDouble(sup_hi, Digits))

         if (!SellCloseSignal)
            if (UseSupLowforSellTP)
               if (!CloseEnough(sup_lo, 0) )
                  if (Ask <= sup_lo_with_spread)
                  {
                     SellCloseSignal = true;
                     if (ShowAlertWhenTradeCloses)
                        Alert(Symbol(), " market is within a support zone. All sell trades should have closed at TP.");
                  }//if (Ask <= NormalizeDouble(sup_lo, Digits))

         if (!SellCloseSignal)
            if (UseResHighforSellSL)
               if (!CloseEnough(res_hi, 0) )
                  if (Ask >= res_hi_with_spread)
                  {
                     SellCloseSignal = true;
                     if (ShowAlertWhenTradeCloses)
                        Alert(Symbol(), " market is within a resistance zone. All sell trades should have closed at SL.");
                  }//if (Ask >= NormalizeDouble(res_hi, Digits))

         if (!SellCloseSignal)
            if (UseResLowforSellSL)
               if (!CloseEnough(res_lo, 0) )
                  if (Ask >= res_lo_with_spread)
                  {
                     SellCloseSignal = true;
                     if (ShowAlertWhenTradeCloses)
                        Alert(Symbol(), " market is within a resistance zone. All sell trades should have closed at SL.");
                  }//if (Ask >= NormalizeDouble(res_lo, Digits))

      }//if (SellOpen)
   }//if (UseSuppRes)

}//void ReadIndicatorValues()
//End Indicator module
////////////////////////////////////////////////////////////////////////////////////////

bool LookForTradeClosure(int ticket)
{
   //Close the trade if the close conditions are met.
   //Called from within CountOpenTrades(). Returns true if a close is needed and succeeds, so that COT can increment cc,
   //else returns false

   if (!BetterOrderSelect(ticket, SELECT_BY_TICKET) ) return(true);
   if (BetterOrderSelect(ticket, SELECT_BY_TICKET) && OrderCloseTime() > 0) return(true);

   bool CloseThisTrade = false;

   string LineName = TpPrefix + DoubleToStr(ticket, 0);
   //Work with the lines on the chart that represent the hidden tp/sl
   double take = ObjectGet(LineName, OBJPROP_PRICE1);
   if (CloseEnough(take, 0) ) take = OrderTakeProfit();
   LineName = SlPrefix + DoubleToStr(ticket, 0);
   double stop = ObjectGet(LineName, OBJPROP_PRICE1);
   if (CloseEnough(stop, 0) ) stop = OrderStopLoss();


   ///////////////////////////////////////////////////////////////////////////////////////////////////////////
   if (OrderType() == OP_BUY || OrderType() == OP_BUYSTOP || OrderType() == OP_BUYLIMIT)
   {
      //TP
      if (Bid >= take && !CloseEnough(take, 0) && !CloseEnough(take, OrderTakeProfit()) ) CloseThisTrade = true;
      //SL
      if (Bid <= stop && !CloseEnough(stop, 0)  && !CloseEnough(stop, OrderStopLoss())) CloseThisTrade = true;

      //Close trade on opposite direction signal
      if (BuyCloseSignal)
         CloseThisTrade = true;

   }//if (OrderType() == OP_BUY)

   ///////////////////////////////////////////////////////////////////////////////////////////////////////////
   if (OrderType() == OP_SELL || OrderType() == OP_SELLSTOP || OrderType() == OP_SELLLIMIT)
   {
      //TP
      if (Bid <= take && !CloseEnough(take, 0) && !CloseEnough(take, OrderTakeProfit()) ) CloseThisTrade = true;
      //SL
      if (Bid >= stop && !CloseEnough(stop, 0)  && !CloseEnough(stop, OrderStopLoss())) CloseThisTrade = true;


      //Close trade on opposite direction signal
      if (SellCloseSignal)
         CloseThisTrade = true;

   }//if (OrderType() == OP_SELL)

   ///////////////////////////////////////////////////////////////////////////////////////////////////////////
   if (CloseThisTrade)
   {
      bool result = false;

      if (OrderType() < 2)//Market orders
         result = CloseOrder(ticket);
      else
         result = OrderDelete(ticket, clrNONE);

      //Actions when trade close succeeds
      if (result)
      {
         DeletePendingPriceLines();
         TicketNo = -1;//TicketNo is the most recently trade opened, so this might need editing in a multi-trade EA
         OpenTrades--;//Rather than OpenTrades = 0 to cater for multi-trade EA's
         return(true);//Makes CountOpenTrades increment cc to avoid missing out ccounting a trade
      }//if (result)

      //Actions when trade close fails
      if (!result)
      {
         return(false);//Do not increment cc
      }//if (!result)
   }//if (CloseThisTrade)

   //Got this far, so no trade closure
   return(false);//Do not increment cc

}//End bool LookForTradeClosure()
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CloseAllTrades(int type)
{

   ForceTradeClosure= false;

   if (OrdersTotal() == 0) return;

   bool result = false;
   for (int pass = 0; pass <= 1; pass++)
   {
      if (OrdersTotal() == 0 || OpenTrades == 0)
         break;
      for (int cc = ArraySize(FifoTicket) - 1; cc >= 0; cc--)
      {
         if (!BetterOrderSelect(FifoTicket[cc], SELECT_BY_TICKET, MODE_TRADES) ) continue;
         if (OrderMagicNumber() != MagicNumber) continue;
         if (OrderSymbol() != Symbol() ) continue;
         if (OrderType() != type)
            if (type != AllTrades)
               continue;

         while(IsTradeContextBusy()) Sleep(100);
         if (OrderType() < 2)
         {
            result = OrderClose(OrderTicket(), OrderLots(), OrderClosePrice(), 1000, CLR_NONE);
            if (result)
            {
               cc++;
               OpenTrades--;
            }//(result)

            if (!result) ForceTradeClosure= true;
         }//if (OrderType() < 2)

         if (pass == 1)
            if (OrderType() > 1)
            {
               result = OrderDelete(OrderTicket(), clrNONE);
               if (result)
               {
                  cc++;
                  OpenTrades--;
               }//(result)
            if (!result) ForceTradeClosure= true;
            }//if (OrderType() > 1)

      }//for (int cc = ArraySize(FifoTicket) - 1; cc >= 0; cc--)
   }//for (int pass = 0; pass <= 1; pass++)

   //If full closure succeeded, then allow new trading
   if (!ForceTradeClosure)
   {
      OpenTrades = 0;
      BuyOpen = false;
      SellOpen = false;
   }//if (!ForceTradeClosure)

}//End void CloseAllTradesFifo()

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CheckTradingTimes()
{

	// Trade 24 hours if no input is given
	if ( ArraySize( tradeHours ) == 0 ) return ( true );

	// Get local time in minutes from midnight
    int time = TimeHour( TimeCurrent() ) * 60 + TimeMinute( TimeCurrent() );

	// Don't you love this?
	int i = 0;
	while ( time >= tradeHours[i] )
	{
		i++;
		if ( i == ArraySize( tradeHours ) ) break;
	}
	if ( i % 2 == 1 ) return ( true );
	return ( false );
}//End bool CheckTradingTimes2()

//+------------------------------------------------------------------+
//| Initialize Trading Hours Array                                   |
//+------------------------------------------------------------------+
bool initTradingHours()
{
   // Called from init()

   if (DrawSessionStartLine || DrawSessionOpenPriceLine)
      ArrayFree(StartHours);

	// Assume 24 trading if no input found
	if ( tradingHours == "" )
	{
		ArrayFree( tradeHours );
		return ( true );
	}

	int i;

	// Add 00:00 start time if first element is stop time
	if ( StringSubstrOld( tradingHours, 0, 1 ) == "-" )
	{
		tradingHours = StringConcatenate( "+0,", tradingHours );
	}

	// Add delimiter
	if ( StringSubstrOld( tradingHours, StringLen( tradingHours ) - 1) != "," )
	{
		tradingHours = StringConcatenate( tradingHours, "," );
	}

	string lastPrefix = "-";
	i = StringFind( tradingHours, "," );

   if (DrawSessionStartLine || DrawSessionOpenPriceLine)
      int cc = 0;

	while (i != -1)
	{

		// Resize array
		int size = ArraySize( tradeHours );
		ArrayResize( tradeHours, size + 1 );

		// Get part to process
		string part = StringSubstrOld( tradingHours, 0, i );

		// Check start or stop prefix
		string prefix = StringSubstrOld ( part, 0, 1 );
		if ( prefix != "+" && prefix != "-" )
		{
			Print("ERROR IN TRADINGHOURS INPUT (NO START OR CLOSE FOUND), ASSUME 24HOUR TRADING.");
			ArrayResize ( tradeHours, 0 );
			return ( true );
		}

		if ( ( prefix == "+" && lastPrefix == "+" ) || ( prefix == "-" && lastPrefix == "-" ) )
		{
			Print("ERROR IN TRADINGHOURS INPUT (START OR CLOSE IN WRONG ORDER), ASSUME 24HOUR TRADING.");
			ArrayResize ( tradeHours, 0 );
			return ( true );
		}

		lastPrefix = prefix;

		// Convert to time in minutes
		part = StringSubstrOld( part, 1 );

      if (DrawSessionStartLine || DrawSessionOpenPriceLine)
      {
         ArrayResize(StartHours, cc + 1);
         StartHours[cc] = StrToDouble( part );
         //Alert(ArraySize(StartHours), "  ", StartHours[cc]);
         cc++;
      }//if (DrawSessionStartLine || DrawSessionOpenPriceLine)

		double time = StrToDouble( part );
		int hour = MathFloor( time );
		int minutes = MathRound( ( time - hour ) * 100 );

		// Add to array
		tradeHours[size] = 60 * hour + minutes;

		// Trim input string
		tradingHours = StringSubstrOld( tradingHours, i + 1 );
		i = StringFind( tradingHours, "," );
	}//while (i != -1)

	return ( true );
}//End bool initTradingHours()

void DrawSessionStartLines()
{

   //Draws a vertical line to mark the start of the current session and a
   //horizontal line to mark the session open price

   datetime time1 = 0;
   datetime time2 = 0;
   double price = 0;

   //24 hour trading
   if (tradingHours == "")
   {
      //Draw a vertical line marking the start of the session
      if (DrawSessionStartLine)
         DrawVerticalLine(SessionStartLineName, PERIOD_D1, 0, SessionStartLineColour, STYLE_SOLID, 0);

      if (DrawSessionOpenPriceLine)
      {
         //Now a trendline marking the open price
         time1 = iTime(Symbol(), PERIOD_D1, 0);
         time2 = iTime(Symbol(), TradingTimeFrame, 0);
         price = iOpen(Symbol(), PERIOD_D1, 0);

         DrawTrendLine(SessionOpenPriceLineName, time1, price, time2, price, SessionOpenPriceLineColour, 0, STYLE_SOLID, true);

         return;
      }//if (DrawSessionOpenPriceLine)

   }//if (tradingHours == "")

   //Find the top of the hour shift to mark the open of the session
   int hour = TimeHour(TimeCurrent() );
   int SessionBarShift = 0;
   int SessionStartHour = -1;
   int SessionStartMins = 0;
   int cc = 0;
   int HourBarShift=0;

   double oldPrice = 0;
   if (ObjectFind(SessionOpenPriceLineName) > -1)
      oldPrice = ObjectGet(SessionOpenPriceLineName, OBJPROP_PRICE1);

   //Find which session we are in
   int as = ArraySize(StartHours);
   while (cc < as)
   {
      hour = TimeHour(iTime(Symbol(), PERIOD_H1, cc));

      if (hour >= StartHours[cc])
      {
         SessionStartHour = StartHours[cc];
         SessionStartMins = MathRound( ( SessionStartHour - StartHours[cc] ) * 100 ) * -1;
      }//if (hour >= StartHours[cc])

      cc = cc + 2;
   }//while (cc < as))


   //We have the session start bar, so we need the bar shift in between then and now
   SessionBarShift = 0;//In case we are in the first hour of the session
   while (TimeHour(iTime(Symbol(), PERIOD_M1, SessionBarShift) ) != SessionStartHour)
   {
      //Alert(TimeHour(iTime(Symbol(), PERIOD_H1, SessionBarShift)));
      SessionBarShift++;
      if (SessionBarShift >= iBars(Symbol(), PERIOD_M1))
         break;
   }//while (TimeHour(iTime(Symbol(), PERIOD_H1, SessionBarShift) ) != SessionStartHour)

   //Add minutes to the shift
   SessionBarShift+= 59;
   SessionBarShift-= SessionStartMins;


   //Draw a vertical line marking the start of the session
   if (DrawSessionStartLine)
      DrawVerticalLine(SessionStartLineName, PERIOD_M1, SessionBarShift, SessionStartLineColour, STYLE_SOLID, 0);

   if (DrawSessionOpenPriceLine)
   {
      //Now a trendline marking the open price
      time1 = iTime(Symbol(), PERIOD_M1, SessionBarShift);
      time2 = iTime(Symbol(), TradingTimeFrame, 0);
      price = iOpen(Symbol(), PERIOD_M1, SessionBarShift);

      if (!CloseEnough(price, oldPrice) )
         DrawTrendLine(SessionOpenPriceLineName, time1, price, time2, price, SessionOpenPriceLineColour, 0, STYLE_SOLID, true);
   }//if (DrawSessionOpenPriceLine)


}//End void DrawSessionStartLines()

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CountOpenTrades()
{
   //Not all these will be needed. Which ones are depends on the individual EA.
   //Market Buy trades
   BuyOpen=false;
   MarketBuysCount=0;
   LatestBuyPrice=0; EarliestBuyPrice=0; HighestBuyPrice=0; LowestBuyPrice=million;
   BuyTicketNo=-1; HighestBuyTicketNo=-1; LowestBuyTicketNo=-1; LatestBuyTicketNo=-1; EarliestBuyTicketNo=-1;
   BuyPipsUpl=0;
   BuyCashUpl=0;
   LatestBuyTradeTime=0;
   EarliestBuyTradeTime=TimeCurrent();

   //Market Sell trades
   SellOpen=false;
   MarketSellsCount=0;
   LatestSellPrice=0; EarliestSellPrice=0; HighestSellPrice=0; LowestSellPrice=million;
   SellTicketNo=-1; HighestSellTicketNo=-1; LowestSellTicketNo=-1; LatestSellTicketNo=-1; EarliestSellTicketNo=-1;;
   SellPipsUpl=0;
   SellCashUpl=0;
   LatestSellTradeTime=0;
   EarliestSellTradeTime=TimeCurrent();

   //BuyStop trades
   BuyStopOpen=false;
   BuyStopsCount=0;
   LatestBuyStopPrice=0; EarliestBuyStopPrice=0; HighestBuyStopPrice=0; LowestBuyStopPrice=million;
   BuyStopTicketNo=-1; HighestBuyStopTicketNo=-1; LowestBuyStopTicketNo=-1; LatestBuyStopTicketNo=-1; EarliestBuyStopTicketNo=-1;;
   LatestBuyStopTradeTime=0;
   EarliestBuyStopTradeTime=TimeCurrent();

   //BuyLimit trades
   BuyLimitOpen=false;
   BuyLimitsCount=0;
   LatestBuyLimitPrice=0; EarliestBuyLimitPrice=0; HighestBuyLimitPrice=0; LowestBuyLimitPrice=million;
   BuyLimitTicketNo=-1; HighestBuyLimitTicketNo=-1; LowestBuyLimitTicketNo=-1; LatestBuyLimitTicketNo=-1; EarliestBuyLimitTicketNo=-1;;
   LatestBuyLimitTradeTime=0;
   EarliestBuyLimitTradeTime=TimeCurrent();

   /////SellStop trades
   SellStopOpen=false;
   SellStopsCount=0;
   LatestSellStopPrice=0; EarliestSellStopPrice=0; HighestSellStopPrice=0; LowestSellStopPrice=million;
   SellStopTicketNo=-1; HighestSellStopTicketNo=-1; LowestSellStopTicketNo=-1; LatestSellStopTicketNo=-1; EarliestSellStopTicketNo=-1;;
   LatestSellStopTradeTime=0;
   EarliestSellStopTradeTime=TimeCurrent();

   //SellLimit trades
   SellLimitOpen=false;
   SellLimitsCount=0;
   LatestSellLimitPrice=0; EarliestSellLimitPrice=0; HighestSellLimitPrice=0; LowestSellLimitPrice=million;
   SellLimitTicketNo=-1; HighestSellLimitTicketNo=-1; LowestSellLimitTicketNo=-1; LatestSellLimitTicketNo=-1; EarliestSellLimitTicketNo=-1;;
   LatestSellLimitTradeTime=0;
   EarliestSellLimitTradeTime=TimeCurrent();

   //Not related to specific order types
   MarketTradesTotal = 0;
   TicketNo=-1;OpenTrades=0;
   LatestTradeTime=0; EarliestTradeTime=TimeCurrent();//More specific times are in each individual section
   LatestTradeTicketNo=-1; EarliestTradeTicketNo=-1;
   PipsUpl=0;//For keeping track of the pips PipsUpl of multi-trade/hedged positions
   CashUpl=0;//For keeping track of the cash PipsUpl of multi-trade/hedged positions


   //FIFO ticket resize
   ArrayResize(FifoTicket, 0);



   int type;//Saves the OrderType() for consulatation later in the function


   if (OrdersTotal() == 0) return;

   //Iterating backwards through the orders list caters more easily for closed trades than iterating forwards
   for (int cc = OrdersTotal() - 1; cc >= 0; cc--)
   {
      bool TradeWasClosed = false;//See 'check for possible trade closure'

      //Ensure the trade is still open
      if (!BetterOrderSelect(cc, SELECT_BY_POS, MODE_TRADES) ) continue;
      //Ensure the EA 'owns' this trade
      if (OrderSymbol() != Symbol() ) continue;
      if (OrderMagicNumber() != MagicNumber) continue;
      if (OrderCloseTime() > 0) continue;

      //The time of the most recent trade
      if (OrderOpenTime() > LatestTradeTime)
      {
         LatestTradeTime = OrderOpenTime();
         LatestTradeTicketNo = OrderTicket();
      }//if (OrderOpenTime() > LatestTradeTime)

      //The time of the earliest trade
      if (OrderOpenTime() < EarliestTradeTime)
      {
         EarliestTradeTime = OrderOpenTime();
         EarliestTradeTicketNo = OrderTicket();
      }//if (OrderOpenTime() < EarliestTradeTime)

      //All conditions passed, so carry on
      type = OrderType();//Store the order type

      if (!CloseEnough(OrderTakeProfit(), 0) )
         TpSet = true;
      if (!CloseEnough(OrderStopLoss(), 0) )
         SlSet = true;

      OpenTrades++;
      //Store the latest trade sent. Most of my EA's only need this final ticket number as either they are single trade
      //bots or the last trade in the sequence is the important one. Adapt this code for your own use.
      if (TicketNo  == -1) TicketNo = OrderTicket();

      //Store ticket numbers for FIFO
      ArrayResize(FifoTicket, OpenTrades + 1);
      FifoTicket[OpenTrades] = OrderTicket();


      //The next line of code calculates the pips upl of an open trade. As yet, I have done nothing with it.
      //something = CalculateTradeProfitInPips()

      double pips = 0;

      //Buile up the position picture of market trades
      if (OrderType() < 2)
      {
         CashUpl+= (OrderProfit() + OrderSwap() + OrderCommission());
         MarketTradesTotal++;
         pips = CalculateTradeProfitInPips(OrderType());
         PipsUpl+= pips;

         //Buys
         if (OrderType() == OP_BUY)
         {
            BuyOpen = true;
            BuyTicketNo = OrderTicket();
            MarketBuysCount++;
            BuyPipsUpl+= pips;
            BuyCashUpl+= (OrderProfit() + OrderSwap() + OrderCommission());

            //Latest trade
            if (OrderOpenTime() > LatestBuyTradeTime)
            {
               LatestBuyTradeTime = OrderOpenTime();
               LatestBuyPrice = OrderOpenPrice();
               LatestBuyTicketNo = OrderTicket();
            }//if (OrderOpenTime() > LatestBuyTradeTime)

            //Furthest back in time
            if (OrderOpenTime() < EarliestBuyTradeTime)
            {
               EarliestBuyTradeTime = OrderOpenTime();
               EarliestBuyPrice = OrderOpenPrice();
               EarliestBuyTicketNo = OrderTicket();
            }//if (OrderOpenTime() < EarliestBuyTradeTime)

            //Highest trade price
            if (OrderOpenPrice() > HighestBuyPrice)
            {
               HighestBuyPrice = OrderOpenPrice();
               HighestBuyTicketNo = OrderTicket();
            }//if (OrderOpenPrice() > HighestBuyPrice)

            //Lowest trade price
            if (OrderOpenPrice() < LowestBuyPrice)
            {
               LowestBuyPrice = OrderOpenPrice();
               LowestBuyTicketNo = OrderTicket();
            }//if (OrderOpenPrice() > LowestBuyPrice)

         }//if (OrderType() == OP_BUY)

         //Sells
         if (OrderType() == OP_SELL)
         {
            SellOpen = true;
            SellTicketNo = OrderTicket();
            MarketSellsCount++;
            SellPipsUpl+= pips;
            SellCashUpl+= (OrderProfit() + OrderSwap() + OrderCommission());

            //Latest trade
            if (OrderOpenTime() > LatestSellTradeTime)
            {
               LatestSellTradeTime = OrderOpenTime();
               LatestSellPrice = OrderOpenPrice();
               LatestSellTicketNo = OrderTicket();
            }//if (OrderOpenTime() > LatestSellTradeTime)

            //Furthest back in time
            if (OrderOpenTime() < EarliestSellTradeTime)
            {
               EarliestSellTradeTime = OrderOpenTime();
               EarliestSellPrice = OrderOpenPrice();
               EarliestSellTicketNo = OrderTicket();
            }//if (OrderOpenTime() < EarliestSellTradeTime)

            //Highest trade price
            if (OrderOpenPrice() > HighestSellPrice)
            {
               HighestSellPrice = OrderOpenPrice();
               HighestSellTicketNo = OrderTicket();
            }//if (OrderOpenPrice() > HighestSellPrice)

            //Lowest trade price
            if (OrderOpenPrice() < LowestSellPrice)
            {
               LowestSellPrice = OrderOpenPrice();
               LowestSellTicketNo = OrderTicket();
            }//if (OrderOpenPrice() > LowestSellPrice)

         }//if (OrderType() == OP_SELL)


      }//if (OrderType() < 2)


      //Build up the position details of stop/limit orders
      if (OrderType() > 1)
      {
         //Buystops
         if (OrderType() == OP_BUYSTOP)
         {
            BuyStopOpen = true;
            BuyStopTicketNo = OrderTicket();
            BuyStopsCount++;

            //Latest trade
            if (OrderOpenTime() > LatestBuyStopTradeTime)
            {
               LatestBuyStopTradeTime = OrderOpenTime();
               LatestBuyStopPrice = OrderOpenPrice();
               LatestBuyStopTicketNo = OrderTicket();
            }//if (OrderOpenTime() > LatestBuyStopTradeTime)

            //Furthest back in time
            if (OrderOpenTime() < EarliestBuyStopTradeTime)
            {
               EarliestBuyStopTradeTime = OrderOpenTime();
               EarliestBuyStopPrice = OrderOpenPrice();
               EarliestBuyStopTicketNo = OrderTicket();
            }//if (OrderOpenTime() < EarliestBuyStopTradeTime)

            //Highest trade price
            if (OrderOpenPrice() > HighestBuyStopPrice)
            {
               HighestBuyStopPrice = OrderOpenPrice();
               HighestBuyStopTicketNo = OrderTicket();
            }//if (OrderOpenPrice() > HighestBuyStopPrice)

            //Lowest trade price
            if (OrderOpenPrice() < LowestBuyStopPrice)
            {
               LowestBuyStopPrice = OrderOpenPrice();
               LowestBuyStopTicketNo = OrderTicket();
            }//if (OrderOpenPrice() > LowestBuyStopPrice)

         }//if (OrderType() == OP_BUYSTOP)

         //Sellstops
         if (OrderType() == OP_SELLSTOP)
         {
            SellStopOpen = true;
            SellStopTicketNo = OrderTicket();
            SellStopsCount++;

            //Latest trade
            if (OrderOpenTime() > LatestSellStopTradeTime)
            {
               LatestSellStopTradeTime = OrderOpenTime();
               LatestSellStopPrice = OrderOpenPrice();
               LatestSellStopTicketNo = OrderTicket();
            }//if (OrderOpenTime() > LatestSellStopTradeTime)

            //Furthest back in time
            if (OrderOpenTime() < EarliestSellStopTradeTime)
            {
               EarliestSellStopTradeTime = OrderOpenTime();
               EarliestSellStopPrice = OrderOpenPrice();
               EarliestSellStopTicketNo = OrderTicket();
            }//if (OrderOpenTime() < EarliestSellStopTradeTime)

            //Highest trade price
            if (OrderOpenPrice() > HighestSellStopPrice)
            {
               HighestSellStopPrice = OrderOpenPrice();
               HighestSellStopTicketNo = OrderTicket();
            }//if (OrderOpenPrice() > HighestSellStopPrice)

            //Lowest trade price
            if (OrderOpenPrice() < LowestSellStopPrice)
            {
               LowestSellStopPrice = OrderOpenPrice();
               LowestSellStopTicketNo = OrderTicket();
            }//if (OrderOpenPrice() > LowestSellStopPrice)

         }//if (OrderType() == OP_SELLSTOP)

         //Buy limits
         if (OrderType() == OP_BUYLIMIT)
         {
            BuyLimitOpen = true;
            BuyLimitTicketNo = OrderTicket();
            BuyLimitsCount++;

            //Latest trade
            if (OrderOpenTime() > LatestBuyLimitTradeTime)
            {
               LatestBuyLimitTradeTime = OrderOpenTime();
               LatestBuyLimitPrice = OrderOpenPrice();
               LatestBuyLimitTicketNo = OrderTicket();
            }//if (OrderOpenTime() > LatestBuyLimitTradeTime)

            //Furthest back in time
            if (OrderOpenTime() < EarliestBuyLimitTradeTime)
            {
               EarliestBuyLimitTradeTime = OrderOpenTime();
               EarliestBuyLimitPrice = OrderOpenPrice();
               EarliestBuyLimitTicketNo = OrderTicket();
            }//if (OrderOpenTime() < EarliestBuyLimitTradeTime)

            //Highest trade price
            if (OrderOpenPrice() > HighestBuyLimitPrice)
            {
               HighestBuyLimitPrice = OrderOpenPrice();
               HighestBuyLimitTicketNo = OrderTicket();
            }//if (OrderOpenPrice() > HighestBuyLimitPrice)

            //Lowest trade price
            if (OrderOpenPrice() < LowestBuyLimitPrice)
            {
               LowestBuyLimitPrice = OrderOpenPrice();
               LowestBuyLimitTicketNo = OrderTicket();
            }//if (OrderOpenPrice() > LowestBuyLimitPrice)

         }//if (OrderType() == OP_BUYLIMIT)

         //Sell limits
         if (OrderType() == OP_SELLLIMIT)
         {
            SellLimitOpen = true;
            SellLimitTicketNo = OrderTicket();
            SellLimitsCount++;

            //Latest trade
            if (OrderOpenTime() > LatestSellLimitTradeTime)
            {
               LatestSellLimitTradeTime = OrderOpenTime();
               LatestSellLimitPrice = OrderOpenPrice();
               LatestSellLimitTicketNo = OrderTicket();
            }//if (OrderOpenTime() > LatestSellLimitTradeTime)

            //Furthest back in time
            if (OrderOpenTime() < EarliestSellLimitTradeTime)
            {
               EarliestSellLimitTradeTime = OrderOpenTime();
               EarliestSellLimitPrice = OrderOpenPrice();
               EarliestSellLimitTicketNo = OrderTicket();
            }//if (OrderOpenTime() < EarliestSellLimitTradeTime)

            //Highest trade price
            if (OrderOpenPrice() > HighestSellLimitPrice)
            {
               HighestSellLimitPrice = OrderOpenPrice();
               HighestSellLimitTicketNo = OrderTicket();
            }//if (OrderOpenPrice() > HighestSellLimitPrice)

            //Lowest trade price
            if (OrderOpenPrice() < LowestSellLimitPrice)
            {
               LowestSellLimitPrice = OrderOpenPrice();
               LowestSellLimitTicketNo = OrderTicket();
            }//if (OrderOpenPrice() > LowestSellLimitPrice)

         }//if (OrderType() == OP_SELLLIMIT)


      }//if (OrderType() > 1)





      if (CloseEnough(OrderStopLoss(), 0) && !CloseEnough(StopLoss, 0)) InsertStopLoss(OrderTicket());
      if (CloseEnough(OrderTakeProfit(), 0) && !CloseEnough(TakeProfit, 0)) InsertTakeProfit(OrderTicket() );

      //Replace missing tp and sl lines
      if (HiddenPips > 0) ReplaceMissingSlTpLines();

      TradeWasClosed = LookForTradeClosure(OrderTicket() );
      if (TradeWasClosed)
      {
         if (type == OP_BUY) BuyOpen = false;//Will be reset if subsequent trades are buys that are not closed
         if (type == OP_SELL) SellOpen = false;//Will be reset if subsequent trades are sells that are not closed
         cc++;
         continue;
      }//if (TradeWasClosed)

      //Profitable trade management
      if (OrderProfit() > 0)
      {
         TradeManagementModule(OrderTicket() );
      }//if (OrderProfit() > 0)



   }//for (int cc = OrdersTotal() - 1; cc <= 0; c`c--)

   //Sort ticket numbers for FIFO
   if (ArraySize(FifoTicket) > 0)
      ArraySort(FifoTicket, WHOLE_ARRAY, 0, MODE_DESCEND);




}//End void CountOpenTrades();
//+------------------------------------------------------------------+


void InsertStopLoss(int ticket)
{
   //Inserts a stop loss if the ECN crim managed to swindle the original trade out of the modification at trade send time
   //Called from CountOpenTrades() if StopLoss > 0 && OrderStopLoss() == 0.

   if (!BetterOrderSelect(ticket, SELECT_BY_TICKET)) return;
   if (OrderCloseTime() > 0) return;//Somehow, we are examining a closed trade
   if (OrderStopLoss() > 0) return;//Function called unnecessarily.

   while(IsTradeContextBusy()) Sleep(100);

   double stop;

   if (OrderType() == OP_BUY)
   {
      stop = CalculateStopLoss(OP_BUY, OrderOpenPrice());
   }//if (OrderType() == OP_BUY)

   if (OrderType() == OP_SELL)
   {
      stop = CalculateStopLoss(OP_SELL, OrderOpenPrice());
   }//if (OrderType() == OP_SELL)

   if (CloseEnough(stop, 0) ) return;

   //In case some errant behaviour/code creates a sl the wrong side of the market, which would cause an instant close.
   if (OrderType() == OP_BUY && stop > OrderOpenPrice() )
   {
      stop = 0;
      ReportError(" InsertStopLoss()", " stop loss > market ");
   }//if (OrderType() == OP_BUY && take < OrderOpenPrice() )

   if (OrderType() == OP_SELL && stop < OrderOpenPrice() )
   {
      stop = 0;
      ReportError(" InsertStopLoss()", " stop loss > market ");
   }//if (OrderType() == OP_SELL && take > OrderOpenPrice() )


   if (!CloseEnough(stop, OrderStopLoss()))
   {
      bool result = ModifyOrder(OrderTicket(), OrderOpenPrice(), stop, OrderTakeProfit(), OrderExpiration(), clrNONE, __FUNCTION__, slim);
   }//if (!CloseEnough(stop, OrderStopLoss()))

}//End void InsertStopLoss(int ticket)

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void InsertTakeProfit(int ticket)
{
   //Inserts a TP if the ECN crim managed to swindle the original trade out of the modification at trade send time
   //Called from CountOpenTrades() if TakeProfit > 0 && OrderTakeProfit() == 0.

   if (!BetterOrderSelect(ticket, SELECT_BY_TICKET)) return;
   if (OrderCloseTime() > 0) return;//Somehow, we are examining a closed trade
   if (!CloseEnough(OrderTakeProfit(), 0) ) return;//Function called unnecessarily.

   while(IsTradeContextBusy()) Sleep(100);

   double take;

   if (OrderType() == OP_BUY)
   {
      take = CalculateTakeProfit(OP_BUY, OrderOpenPrice(), OrderStopLoss());
   }//if (OrderType() == OP_BUY)

   if (OrderType() == OP_SELL)
   {
      take = CalculateTakeProfit(OP_SELL, OrderOpenPrice(), OrderStopLoss());
   }//if (OrderType() == OP_SELL)

   if (CloseEnough(take, 0) ) return;

   //In case some errant behaviour/code creates a tp the wrong side of the market, which would cause an instant close.
   if (OrderType() == OP_BUY && take < OrderOpenPrice()  && !CloseEnough(take, 0) )
   {
      take = 0;
      ReportError(" InsertTakeProfit()", " take profit < market ");
      return;
   }//if (OrderType() == OP_BUY && take < OrderOpenPrice() )

   if (OrderType() == OP_SELL && take > OrderOpenPrice() )
   {
      take = 0;
      ReportError(" InsertTakeProfit()", " take profit < market ");
      return;
   }//if (OrderType() == OP_SELL && take > OrderOpenPrice() )


   if (!CloseEnough(take, OrderTakeProfit()) )
   {
      bool result = ModifyOrder(OrderTicket(), OrderOpenPrice(), OrderStopLoss(), take, OrderExpiration(), clrNONE, __FUNCTION__, slim);
   }//if (!CloseEnough(take, OrderTakeProfit()) )

}//End void InsertTakeProfit(int ticket)
////////////////////////////////////////////////////////////////////////////////////////
//Pending trade price lines module.
//Doubles up by providing missing lines for the stealth stuff
void DrawPendingPriceLines()
{
   //This function will work for a full pending-trade EA.
   //The pending tp/sl can be used for hiding the stops in a market-trading ea

   /*
   ObjectDelete(pendingpriceline);
   ObjectCreate(pendingpriceline, OBJ_HLINE, 0, TimeCurrent(), PendingPrice);
   if (PendingBuy) ObjectSet(pendingpriceline, OBJPROP_COLOR, Green);
   if (PendingSell) ObjectSet(pendingpriceline, OBJPROP_COLOR, Red);
   ObjectSet(pendingpriceline, OBJPROP_WIDTH, 1);
   ObjectSet(pendingpriceline, OBJPROP_STYLE, STYLE_DASH);
   */
   string LineName = TpPrefix + DoubleToStr(TicketNo, 0);//TicketNo is set by the calling function - either CountOpenTrades or DoesTradeExist
   HiddenTakeProfit = 0;
   if (TicketNo > -1 && OrderTakeProfit() > 0)
   {
      if (OrderType() == OP_BUY || OrderType() == OP_BUYSTOP || OrderType() == OP_BUYLIMIT)
      {
         HiddenTakeProfit = NormalizeDouble(OrderTakeProfit() - (HiddenPips / factor), Digits);
      }//if (OrderType() == OP_BUY)

      if (OrderType() == OP_SELL)
      {
         HiddenTakeProfit = NormalizeDouble(OrderTakeProfit() + (HiddenPips / factor), Digits);
      }//if (OrderType() == OP_BUY)
   }//if (TicketNo > -1 && OrderTakeProfit() > 0)

   if (HiddenTakeProfit > 0 && ObjectFind(LineName) == -1)
   {
      ObjectDelete(LineName);
      ObjectCreate(LineName, OBJ_HLINE, 0, TimeCurrent(), HiddenTakeProfit);
      ObjectSet(LineName, OBJPROP_COLOR, Green);
      ObjectSet(LineName, OBJPROP_WIDTH, 1);
      ObjectSet(LineName, OBJPROP_STYLE, STYLE_DOT);
   }//if (HiddenTakeProfit > 0)


   LineName = SlPrefix + DoubleToStr(TicketNo, 0);//TicketNo is set by the calling function - either CountOpenTrades or DoesTradeExist
   HiddenStopLoss = 0;
   if (TicketNo > -1 && OrderStopLoss() > 0)
   {
      if (OrderType() == OP_BUY || OrderType() == OP_BUYSTOP || OrderType() == OP_BUYLIMIT)
      {
         HiddenStopLoss = NormalizeDouble(OrderStopLoss() + (HiddenPips / factor), Digits);
      }//if (OrderType() == OP_BUY)

      if (OrderType() == OP_SELL || OrderType() == OP_SELLSTOP || OrderType() == OP_SELLLIMIT)
      {
         HiddenStopLoss = NormalizeDouble(OrderStopLoss() - (HiddenPips / factor), Digits);
      }//if (OrderType() == OP_BUY)
   }//if (TicketNo > -1 && OrderStopLoss() > 0)

   if (HiddenStopLoss > 0 && ObjectFind(LineName) == -1)
   {
      ObjectDelete(LineName);
      ObjectCreate(LineName, OBJ_HLINE, 0, TimeCurrent(), HiddenStopLoss);
      ObjectSet(LineName, OBJPROP_COLOR, Red);
      ObjectSet(LineName, OBJPROP_WIDTH, 1);
      ObjectSet(LineName, OBJPROP_STYLE, STYLE_DOT);
   }//if (HiddenStopLoss > 0)



}//End void DrawPendingPriceLines()
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DeletePendingPriceLines()
{

   //ObjectDelete(pendingpriceline);
   string LineName=TpPrefix+DoubleToStr(TicketNo,0);
   ObjectDelete(LineName);
   LineName=SlPrefix+DoubleToStr(TicketNo,0);
   ObjectDelete(LineName);

}//End void DeletePendingPriceLines()
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ReplaceMissingSlTpLines()
{

   if(OrderTakeProfit()>0 || OrderStopLoss()>0) DrawPendingPriceLines();

}//End void ReplaceMissingSlTpLines()
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DeleteOrphanTpSlLines()
{

   if (ObjectsTotal() == 0) return;

   for (int cc = ObjectsTotal() - 1; cc >= 0; cc--)
   {
      string name = ObjectName(cc);

      if ((StringSubstrOld(name, 0, 2) == TpPrefix || StringSubstrOld(name, 0, 2) == SlPrefix) && ObjectType(name) == OBJ_HLINE)
      {
         int tn = StrToDouble(StringSubstrOld(name, 2));
         if (tn > 0)
         {
            if (!BetterOrderSelect(tn, SELECT_BY_TICKET, MODE_TRADES) || OrderCloseTime() > 0)
            {
               ObjectDelete(name);
            }//if (!BetterOrderSelect(tn, SELECT_BY_TICKET, MODE_TRADES) || OrderCloseTime() > 0)

         }//if (tn > 0)


      }//if (StringSubstrOld(name, 0, 1) == TpPrefix)

   }//for (int cc = ObjectsTotal() - 1; cc >= 0; cc--)


}//End void DeleteOrphanTpSlLines()

//END Pending trade price lines module
////////////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////////////
//TRADE MANAGEMENT MODULE

void ReportError(string function, string message)
{
   //All purpose sl mod error reporter. Called when a sl mod fails

   int err=GetLastError();
   if (err == 1) return;//That bloody 'error but no error' report is a nuisance

   Alert(WindowExpertName(), " ", OrderTicket(), " ", function, message, err,": ",ErrorDescription(err));
   Print(WindowExpertName(), " ", OrderTicket(), " ", function, message, err,": ",ErrorDescription(err));

}//void ReportError()

bool ModifyOrder(int ticket, double price, double stop, double take, datetime expiry, color col, string function, string reason)
{
   //Multi-purpose order modify function

   bool result = OrderModify(ticket, price ,stop , take, expiry, col);

   //Actions when trade close succeeds
   if (result)
   {
      return(true);
   }//if (result)

   //Actions when trade close fails
   if (!result)
      ReportError(function, reason);

   //Got this far, so modify failed
   return(false);

}// End bool ModifyOrder()

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void BreakEvenStopLoss(int ticket) // Move stop loss to breakeven
{

   //Security check
   if (!BetterOrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
      return;

   double NewStop;
   bool result;
   bool modify=false;
   string LineName = SlPrefix + DoubleToStr(OrderTicket(), 0);
   double sl = ObjectGet(LineName, OBJPROP_PRICE1);
   double target = OrderOpenPrice();

   if (OrderType()==OP_BUY)
   {
      if (HiddenPips > 0) target-= (HiddenPips / factor);
      if (OrderStopLoss() >= target) return;
      if (Bid >= OrderOpenPrice () + (BreakEvenPips / factor))
      {
         //Calculate the new stop
         NewStop = NormalizeDouble(OrderOpenPrice()+(BreakEvenProfit / factor), Digits);
         if (HiddenPips > 0)
         {
            if (ObjectFind(LineName) == -1)
            {
               ObjectCreate(LineName, OBJ_HLINE, 0, TimeCurrent(), 0);
               ObjectSet(LineName, OBJPROP_COLOR, Red);
               ObjectSet(LineName, OBJPROP_WIDTH, 1);
               ObjectSet(LineName, OBJPROP_STYLE, STYLE_DOT);
            }//if (ObjectFind(LineName == -1) )

            ObjectMove(LineName, 0, TimeCurrent(), NewStop);
         }//if (HiddenPips > 0)
         modify = true;
      }//if (Bid >= OrderOpenPrice () + (Point*BreakEvenPips) &&
   }//if (OrderType()==OP_BUY)

   if (OrderType()==OP_SELL)
   {
     if (HiddenPips > 0) target+= (HiddenPips / factor);
      if (OrderStopLoss() <= target && OrderStopLoss() > 0) return;
     if (Ask <= OrderOpenPrice() - (BreakEvenPips / factor))
     {
         //Calculate the new stop
         NewStop = NormalizeDouble(OrderOpenPrice()-(BreakEvenProfit / factor), Digits);
         if (HiddenPips > 0)
         {
            if (ObjectFind(LineName) == -1)
            {
               ObjectCreate(LineName, OBJ_HLINE, 0, TimeCurrent(), 0);
               ObjectSet(LineName, OBJPROP_COLOR, Red);
               ObjectSet(LineName, OBJPROP_WIDTH, 1);
               ObjectSet(LineName, OBJPROP_STYLE, STYLE_DOT);
            }//if (ObjectFind(LineName == -1) )

            ObjectMove(LineName, 0, Time[0], NewStop);
         }//if (HiddenPips > 0)
         modify = true;
     }//if (Ask <= OrderOpenPrice() - (Point*BreakEvenPips) && (OrderStopLoss()>OrderOpenPrice()|| OrderStopLoss()==0))
   }//if (OrderType()==OP_SELL)

   //Move 'hard' stop loss whether hidden or not. Don't want to risk losing a breakeven through disconnect.
   if (modify)
   {
      if (NewStop == OrderStopLoss() ) return;
      while (IsTradeContextBusy() ) Sleep(100);
      result = ModifyOrder(OrderTicket(), OrderOpenPrice(), NewStop, OrderTakeProfit(), OrderExpiration(), clrNONE, __FUNCTION__, slm);

      while (IsTradeContextBusy() ) Sleep(100);
      if (PartCloseEnabled && StringSubstr(OrderComment(),0,StringLen(TradeComment)) == TradeComment) bool success = PartCloseOrder(OrderTicket());
   }//if (modify)

} // End BreakevenStopLoss sub

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool PartCloseOrder(int ticket)
{
   //Close PartClosePercent of the initial trade.
   //Return true if close succeeds, else false
   if (!BetterOrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES)) return(true);//in case the trade closed

   bool Success = false;
   double CloseLots = NormalizeLots(OrderSymbol(),OrderLots() * (PartClosePercent / 100));

   Success = OrderClose(ticket, CloseLots, OrderClosePrice(), 1000, Blue); //fxdaytrader, NormalizeLots(...
   if (Success) TradeHasPartClosed = true;//Warns CountOpenTrades() that the OrderTicket() is incorrect.
   if (!Success)
   {
       //mod. fxdaytrader, orderclose-retry if failed with ordercloseprice(). Maybe very seldom, but it can happen, so it does not hurt to implement this:
       while(IsTradeContextBusy()) Sleep(100);
       RefreshRates();
       if (OrderType()==OP_BUY) Success = OrderClose(ticket, CloseLots, MarketInfo(OrderSymbol(),MODE_BID), 5000, Blue);
       if (OrderType()==OP_SELL) Success = OrderClose(ticket, CloseLots, MarketInfo(OrderSymbol(),MODE_ASK), 5000, Blue);
       //end mod.
       //original:
       if (Success) TradeHasPartClosed = true;//Warns CountOpenTrades() that the OrderTicket() is incorrect.

       if (!Success)
       {
         ReportError(" PartCloseOrder()", pcm);
         return (false);
       }
   }//if (!Success)

   //Got this far, so closure succeeded
   return (true);

}//bool PartCloseOrder(int ticket)

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void JumpingStopLoss(int ticket)
{
   // Jump sl by pips and at intervals chosen by user .

   //Security check
   if (!BetterOrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
      return;

   //if (OrderProfit() < 0) return;//Nothing to do
   string LineName = SlPrefix + DoubleToStr(OrderTicket(), 0);
   double sl = ObjectGet(LineName, OBJPROP_PRICE1);
   if (CloseEnough(sl, 0) ) sl = OrderStopLoss();

   //if (CloseEnough(sl, 0) ) return;//No line, so nothing to do
   double NewStop;
   bool modify=false;
   bool result;


    if (OrderType()==OP_BUY)
    {
       if (sl < OrderOpenPrice() ) return;//Not at breakeven yet
       // Increment sl by sl + JumpingStopPips.
       // This will happen when market price >= (sl + JumpingStopPips)
       //if (Bid>= sl + ((JumpingStopPips*2) / factor) )
       if (CloseEnough(sl, 0) ) sl = MathMax(OrderStopLoss(), OrderOpenPrice());
       if (Bid >=  sl + ((JumpingStopPips * 2) / factor) )//George{
       {
          NewStop = NormalizeDouble(sl + (JumpingStopPips / factor), Digits);
          if (AddBEP) NewStop = NormalizeDouble(NewStop + (BreakEvenProfit / factor), Digits);
          if (HiddenPips > 0) ObjectMove(LineName, 0, Time[0], NewStop);
          if (NewStop - OrderStopLoss() >= Point) modify = true;//George again. What a guy
       }// if (Bid>= sl + (JumpingStopPips / factor) && sl>= OrderOpenPrice())
    }//if (OrderType()==OP_BUY)

       if (OrderType()==OP_SELL)
       {
          if (sl > OrderOpenPrice() ) return;//Not at breakeven yet
          // Decrement sl by sl - JumpingStopPips.
          // This will happen when market price <= (sl - JumpingStopPips)
          //if (Bid<= sl - ((JumpingStopPips*2) / factor)) Original code
          if (CloseEnough(sl, 0) ) sl = MathMin(OrderStopLoss(), OrderOpenPrice());
          if (CloseEnough(sl, 0) ) sl = OrderOpenPrice();
          if (Bid <= sl - ((JumpingStopPips * 2) / factor) )//George
          {
             NewStop = NormalizeDouble(sl - (JumpingStopPips / factor), Digits);
             if (AddBEP) NewStop = NormalizeDouble(NewStop - (BreakEvenProfit / factor), Digits);
             if (HiddenPips > 0) ObjectMove(LineName, 0, Time[0], NewStop);
             if (OrderStopLoss() - NewStop >= Point || OrderStopLoss() == 0) modify = true;//George again. What a guy
          }// close if (Bid>= sl + (JumpingStopPips / factor) && sl>= OrderOpenPrice())
       }//if (OrderType()==OP_SELL)



   //Move 'hard' stop loss whether hidden or not. Don't want to risk losing a breakeven through disconnect.
   if (modify)
   {
      while (IsTradeContextBusy() ) Sleep(100);
      result = ModifyOrder(OrderTicket(), OrderOpenPrice(), NewStop, OrderTakeProfit(), OrderExpiration(), clrNONE, __FUNCTION__, slm);
   }//if (modify)

} //End of JumpingStopLoss sub

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void TrailingStopLoss(int ticket)
{

   //Security check
   if (!BetterOrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
      return;

   if (OrderProfit() < 0) return;//Nothing to do
   string LineName = SlPrefix + DoubleToStr(OrderTicket(), 0);
   double sl = ObjectGet(LineName, OBJPROP_PRICE1);
   //if (CloseEnough(sl, 0) ) return;//No line, so nothing to do
   if (CloseEnough(sl, 0) ) sl = OrderStopLoss();
   double NewStop;
   bool modify=false;
   bool result;

    if (OrderType()==OP_BUY)
       {
          if (sl < OrderOpenPrice() ) return;//Not at breakeven yet
          // Increment sl by sl + TrailingStopPips.
          // This will happen when market price >= (sl + JumpingStopPips)
          //if (Bid>= sl + (TrailingStopPips / factor) ) Original code
          if (CloseEnough(sl, 0) ) sl = MathMax(OrderStopLoss(), OrderOpenPrice());
          if (Bid >= sl + (TrailingStopPips / factor) )//George
          {
             NewStop = NormalizeDouble(sl + (TrailingStopPips / factor), Digits);
             if (HiddenPips > 0) ObjectMove(LineName, 0, Time[0], NewStop);
             if (NewStop - OrderStopLoss() >= Point) modify = true;//George again. What a guy
          }//if (Bid >= MathMax(sl,OrderOpenPrice()) + (TrailingStopPips / factor) )//George
       }//if (OrderType()==OP_BUY)

       if (OrderType()==OP_SELL)
       {
          if (sl > OrderOpenPrice() ) return;//Not at breakeven yet
          // Decrement sl by sl - TrailingStopPips.
          // This will happen when market price <= (sl - JumpingStopPips)
          //if (Bid<= sl - (TrailingStopPips / factor) ) Original code
          if (CloseEnough(sl, 0) ) sl = MathMin(OrderStopLoss(), OrderOpenPrice());
          if (CloseEnough(sl, 0) ) sl = OrderOpenPrice();
          if (Bid <= sl  - (TrailingStopPips / factor))//George
          {
             NewStop = NormalizeDouble(sl - (TrailingStopPips / factor), Digits);
             if (HiddenPips > 0) ObjectMove(LineName, 0, Time[0], NewStop);
             if (OrderStopLoss() - NewStop >= Point || OrderStopLoss() == 0) modify = true;//George again. What a guy
          }//if (Bid <= MathMin(sl, OrderOpenPrice() ) - (TrailingStopPips / factor) )//George
       }//if (OrderType()==OP_SELL)


   //Move 'hard' stop loss whether hidden or not. Don't want to risk losing a breakeven through disconnect.
   if (modify)
   {
      while (IsTradeContextBusy() ) Sleep(100);
      result = ModifyOrder(OrderTicket(), OrderOpenPrice(), NewStop, OrderTakeProfit(), OrderExpiration(), clrNONE, __FUNCTION__, slm);
   }//if (modify)

} // End of TrailingStopLoss sub
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CandlestickTrailingStop(int ticket)
{

   //Security check
   if (!BetterOrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
      return;

   //Trails the stop at the hi/lo of the previous candle shifted by the user choice.
   //Only tries to do this once per bar, so an invalid stop error will only be generated once. I could code for
   //a too-close sl, but cannot be arsed. Coders, sort this out for yourselves.

   if (OldCstBars == iBars(NULL, CstTimeFrame)) return;
   OldCstBars = iBars(NULL, CstTimeFrame);

   if (OrderProfit() < 0) return;//Nothing to do
   string LineName = SlPrefix + DoubleToStr(OrderTicket(), 0);
   double sl = ObjectGet(LineName, OBJPROP_PRICE1);
   if (CloseEnough(sl, 0) ) sl = OrderStopLoss();
   double NewStop;
   bool modify=false;
   bool result;

   if (OrderType() == OP_BUY)
   {
      if (iLow(NULL, CstTimeFrame, CstTrailCandles) > sl)
      {
         NewStop = NormalizeDouble(iLow(NULL, CstTimeFrame, CstTrailCandles), Digits);
         //Check that the new stop is > the old. Exit the function if not.
         if (NewStop < OrderStopLoss() || CloseEnough(NewStop, OrderStopLoss()) ) return;
         //Check that the new stop locks in profit, if the user requires this.
         if (TrailMustLockInProfit && NewStop < OrderOpenPrice() ) return;

         if (HiddenPips > 0)
         {
            ObjectMove(LineName, 0, Time[0], NewStop);
            NewStop = NormalizeDouble(NewStop - (HiddenPips / factor), Digits);
         }//if (HiddenPips > 0)
         modify = true;
      }//if (iLow(NULL, CstTimeFrame, CstTrailCandles) > sl)
   }//if (OrderType == OP_BUY)

   if (OrderType() == OP_SELL)
   {
      if (iHigh(NULL, CstTimeFrame, CstTrailCandles) < sl)
      {
         NewStop = NormalizeDouble(iHigh(NULL, CstTimeFrame, CstTrailCandles), Digits);

         //Check that the new stop is < the old. Exit the function if not.
         if (NewStop > OrderStopLoss() || CloseEnough(NewStop, OrderStopLoss()) ) return;
         //Check that the new stop locks in profit, if the user requires this.
         if (TrailMustLockInProfit && NewStop > OrderOpenPrice() ) return;

         if (HiddenPips > 0)
         {
            ObjectMove(LineName, 0, Time[0], NewStop);
            NewStop = NormalizeDouble(NewStop + (HiddenPips / factor), Digits);
         }//if (HiddenPips > 0)
         modify = true;
      }//if (iHigh(NULL, CstTimeFrame, CstTrailCandles) < sl)
   }//if (OrderType() == OP_SELL)

   //Move 'hard' stop loss whether hidden or not. Don't want to risk losing a breakeven through disconnect.
   if (modify)
   {
      while (IsTradeContextBusy() ) Sleep(100);
      result = ModifyOrder(OrderTicket(), OrderOpenPrice(), NewStop, OrderTakeProfit(), OrderExpiration(), clrNONE, __FUNCTION__, slm);
      if (!result)
      {
         OldCstBars = 0;
      }//if (!result)

   }//if (modify)

}//End void CandlestickTrailingStop()
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void TradeManagementModule(int ticket)
{
   // Call the working subroutines one by one.

   //Candlestick trailing stop
   if(UseCandlestickTrailingStop) CandlestickTrailingStop(ticket);

   // Breakeven
   if(BreakEven) BreakEvenStopLoss(ticket);

   // JumpingStop
   if(JumpingStop) JumpingStopLoss(ticket);

   //TrailingStop
   if(TrailingStop) TrailingStopLoss(ticket);

}//void TradeManagementModule()
//END TRADE MANAGEMENT MODULE
////////////////////////////////////////////////////////////////////////////////////////

double CalculateTradeProfitInPips(int type)
{
   //This code supplied by Lifesys. Many thanks Paul.

   //Returns the pips Upl of the currently selected trade. Called by CountOpenTrades()
   double profit;
   // double point = BrokerPoint(OrderSymbol() ); // no real use
   double ask = MarketInfo(OrderSymbol(), MODE_ASK);
   double bid = MarketInfo(OrderSymbol(), MODE_BID);

   if (type == OP_BUY)
   {
      profit = bid - OrderOpenPrice();
   }//if (OrderType() == OP_BUY)

   if (type == OP_SELL)
   {
      profit = OrderOpenPrice() - ask;
   }//if (OrderType() == OP_SELL)
   //profit *= PFactor(OrderSymbol()); // use PFactor instead of point. This line for multi-pair ea's
   profit *= factor; // use PFactor instead of point.

   return(profit); // in real pips
}//double CalculateTradeProfitInPips(int type)
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CloseEnough(double num1,double num2)
{
/*
   This function addresses the problem of the way in which mql4 compares doubles. It often messes up the 8th
   decimal point.
   For example, if A = 1.5 and B = 1.5, then these numbers are clearly equal. Unseen by the coder, mql4 may
   actually be giving B the value of 1.50000001, and so the variable are not equal, even though they are.
   This nice little quirk explains some of the problems I have endured in the past when comparing doubles. This
   is common to a lot of program languages, so watch out for it if you program elsewhere.
   Gary (garyfritz) offered this solution, so our thanks to him.
   */

   if(num1==0 && num2==0) return(true); //0==0
   if(MathAbs(num1 - num2) / (MathAbs(num1) + MathAbs(num2)) < 0.00000001) return(true);

//Doubles are unequal
   return(false);

}//End bool CloseEnough(double num1, double num2)
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int GetPipFactor(string Xsymbol)
{
   //Code from Tommaso's APTM. Thanks Tommaso.

   static const string factor1000[] = {"SEK","TRY","ZAR","MXN"};
   static const string factor100[]  = {"JPY","XAG","SILVER","BRENT","WTI"};
   static const string factor10[]   = {"XAU","GOLD","SP500","US500Cash","US500","Bund"};
   static const string factor1[]    = {"UK100","WS30","DAX30","NAS100","CAC40","FRA40","GER30","ITA40","EUSTX50","JPN225","US30Cash","US30"};

   int j = 0;

   int xFactor=10000;       // correct xFactor for most pairs
   if(MarketInfo(Xsymbol,MODE_DIGITS)<=1) xFactor=1;
   else if(MarketInfo(Xsymbol,MODE_DIGITS)==2) xFactor=10;
   else if(MarketInfo(Xsymbol,MODE_DIGITS)==3) xFactor=100;
   else if(MarketInfo(Xsymbol,MODE_DIGITS)==4) xFactor=1000;
   else if(MarketInfo(Xsymbol,MODE_DIGITS)==5) xFactor=10000;
   else if(MarketInfo(Xsymbol,MODE_DIGITS)==6) xFactor=100000;
   else if(MarketInfo(Xsymbol,MODE_DIGITS)==7) xFactor=1000000;
   for(j=0; j<ArraySize(factor1000); j++)
   {
      if(StringFind(Xsymbol,factor1000[j])!=-1) xFactor=1000;
   }
   for(j=0; j<ArraySize(factor100); j++)
   {
      if(StringFind(Xsymbol,factor100[j])!=-1) xFactor=100;
   }
   for(j=0; j<ArraySize(factor10); j++)
   {
      if(StringFind(Xsymbol,factor10[j])!=-1) xFactor=10;
   }
   for(j=0; j<ArraySize(factor1); j++)
   {
      if(StringFind(Xsymbol,factor1[j])!=-1) xFactor=1;
   }

   return (xFactor);
}//End int GetPipFactor(string Xsymbol)
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void GetSwap(string symbol)
{
   LongSwap=MarketInfo(symbol,MODE_SWAPLONG);
   ShortSwap=MarketInfo(symbol,MODE_SWAPSHORT);

}//End void GetSwap()
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool TooClose()
{
   //Returns false if the previously closed trade and the proposed new trade are sufficiently far apart, else return true. Called from IsTradeAllowed().

   SafetyViolation = false; //For chart feedback
   if (OrdersHistoryTotal() == 0) return(false);

   for (int cc = OrdersHistoryTotal() - 1; cc >= 0; cc--)
   {
      if (!BetterOrderSelect(cc, SELECT_BY_POS, MODE_HISTORY) ) continue;
      if (OrderMagicNumber() != MagicNumber) continue;
      if (OrderSymbol() != Symbol() ) continue;
      if (OrderType() > 1) continue;

      //Examine the OrderCloseTime to see if it closed far enought back in time.
      if (TimeCurrent() - OrderCloseTime() < (MinMinutesBetweenTrades * 60))
         SafetyViolation = true;
      break;
   }//for (int cc = OrdersHistoryTotal() - 1; cc >= 0; cc--)

   //Got this far, so there is no disqualifying trade in the history
   return(SafetyViolation);

}//bool TooClose()
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsClosedTradeRogue()
{
   //~ Safety feature. Sometimes an unexpected concatenation of inputs choice and logic error can cause rapid opening-closing of trades. Detect a closed trade and check that is was not a rogue. Examine trades closed within the last 5 minutes.

   //~ If it is a rogue:
   //~ * Show a warning alert.
   //~ * Send an email alert.
   //~ * Suspend the robot

   if (OrdersHistoryTotal() == 0) return(false);

   datetime latestTime = TimeCurrent() - ( 5 * 60 );

   datetime duration = -1; //impossible value

   //We cannot guarantee that the most recent trade shown in our History tab is actually the most recent on the crim's server - CraptT4 again. pah has supplied this code to ensure that we are examining the latest trade. Many thanks, Paul.
   // look for trades that closed within the last 5 minutes
   // otherwise we will always find the last rogue trade
   // even when that happened some time ago and can be ignored

   for ( int i = OrdersHistoryTotal()-1; i >= 0; i-- )
   {
      if ( ! BetterOrderSelect(i, SELECT_BY_POS, MODE_HISTORY) ) continue;

      if ( OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol() ) continue;

      if ( OrderCloseTime() >= latestTime )
      {
         latestTime = OrderCloseTime();
         duration    = OrderCloseTime() - OrderOpenTime();
      }//if ( OrderCloseTime() >= latestTime )

   }//for ( int i = OrdersHistoryTotal()-1; i >= 0; i-- )


   bool rogue = ( duration >= 0 ) && ( duration < ( MinMinutesBetweenTradeOpenClose * 60) );

   if (rogue)
   {
      RobotSuspended = true;
      Alert(Symbol(), " ", WindowExpertName() , " possible rogue trade.");
      SendMail("Possible rogue trade warning ", Symbol() + " " + WindowExpertName() + " possible rogue trade.");
      Comment(NL, Gap, "****************** ROBOT SUSPENDED. POSSIBLE ROGUE TRADING ACTIVITY. REMOVE THIS EA IMMEDIATELY ****************** ");
      return(true);//Too close, so disallow the trade

   }//if (rogue)

   //Got this far, so there is no rogue trade
   return(false);



}//bool IsClosedTradeRogue()
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DrawTrendLine(string name,datetime time1,double val1,datetime time2,double val2,color col,int width,int style,bool ray)
{
//Plots a trendline with the given parameters

   ObjectDelete(name);

   ObjectCreate(name,OBJ_TREND,0,time1,val1,time2,val2);
   ObjectSet(name,OBJPROP_COLOR,col);
   ObjectSet(name,OBJPROP_WIDTH,width);
   ObjectSet(name,OBJPROP_STYLE,style);
   ObjectSet(name,OBJPROP_RAY,ray);

}//End void DrawLine()
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DrawHorizontalLine(string name,double price,color col,int style,int width)
{

   ObjectDelete(name);

   ObjectCreate(name,OBJ_HLINE,0,TimeCurrent(),price);
   ObjectSet(name,OBJPROP_COLOR,col);
   ObjectSet(name,OBJPROP_STYLE,style);
   ObjectSet(name,OBJPROP_WIDTH,width);

}//void DrawLine(string name, double price, color col)
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DrawVerticalLine(string name, int tf, int shift,color col,int style,int width)
{
//ObjectCreate(vline,OBJ_VLINE,0,iTime(NULL, TimeFrame, 0), 0);
   ObjectDelete(name);
   ObjectCreate(name,OBJ_VLINE,0,iTime(Symbol(),tf,shift),0);
   ObjectSet(name,OBJPROP_COLOR,col);
   ObjectSet(name,OBJPROP_STYLE,style);
   ObjectSet(name,OBJPROP_WIDTH,width);

}//void DrawVerticalLine()

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MarginCheck()
{

   EnoughMargin = true;//For user display
   MarginMessage = "";
   if (UseScoobsMarginCheck && OpenTrades > 0)
   {
      if(AccountMargin() > (AccountFreeMargin()/100))
      {
         MarginMessage = "There is insufficient margin to allow trading. You might want to turn off the UseScoobsMarginCheck input.";
         return(false);
      }//if(AccountMargin() > (AccountFreeMargin()/100))

   }//if (UseScoobsMarginCheck)


   if (UseForexKiwi && AccountMargin() > 0)
   {

      double ml = NormalizeDouble(AccountEquity() / AccountMargin() * 100, 2);
      if (ml < FkMinimumMarginPercent)
      {
         MarginMessage = StringConcatenate("There is insufficient margin percent to allow trading. ", DoubleToStr(ml, 2), "%");
         return(false);
      }//if (ml < FkMinimumMarginPercent)
   }//if (UseForexKiwi && AccountMargin() > 0)


   //Got this far, so there is sufficient margin for trading
   return(true);
}//End bool MarginCheck()
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string PeriodText(int per)
{

	switch (per)
	{
   	case PERIOD_M1:
   		return("M1");
   	case PERIOD_M5:
   		return("M5");
   	case PERIOD_M15:
   		return("M15");
   	case PERIOD_M30:
   		return("M30");
   	case PERIOD_H1:
   		return("H1");
   	case PERIOD_H4:
   		return("H4");
   	case PERIOD_D1:
   		return("D1");
   	case PERIOD_MN1:
   		return("MN1");
   	default:
   		return("");
	}

}//End string PeriodText(int per)

//+------------------------------------------------------------------+
//  Code to check that there are at least 100 bars of history in
//  the sym / per in the passed params
//+------------------------------------------------------------------+
bool HistoryOK(string sym,int per)
  {

   double tempArray[][6];  //used for the call to ArrayCopyRates()

                           //get the number of bars
   int bars=iBars(sym,per);
//and report it in the log
   Print("Checking ",sym," for complete data.... number of ",PeriodText(per)," bars = ",bars);

   if(bars<100)
     {
      //we didn't have enough, so set the comment and try to trigger the DL another way
      Comment("Symbol ",sym," -- Waiting for "+PeriodText(per)+" data.");
      ArrayCopyRates(tempArray,sym,per);
      int error=GetLastError();
      if(error!=0) Print(sym," - requesting data from the server...");

      //return false so the caller knows we don't have the data
      return(false);
     }//if (bars < 100)

//if we got here, the data is fine, so clear the comment and return true
   Comment("");
   return(true);

  }//End bool HistoryOK(string sym,int per)

//+------------------------------------------------------------------+
//| NormalizeLots(string symbol, double lots)                        |
//+------------------------------------------------------------------+
//function added by fxdaytrader
//Lot size must be adjusted to be a multiple of lotstep, which may not be a power of ten on some brokers
//see also the original function by WHRoeder, http://forum.mql4.com/45425#564188, fxdaytrader
double NormalizeLots(string symbol,double lots)
{
   if(MathAbs(lots)==0.0) return(0.0); //just in case ... otherwise it may happen that after rounding 0.0 the result is >0 and we have got a problem, fxdaytrader
   double ls=MarketInfo(symbol,MODE_LOTSTEP);
   lots=MathMin(MarketInfo(symbol,MODE_MAXLOT),MathMax(MarketInfo(symbol,MODE_MINLOT),lots)); //check if lots >= min. lots && <= max. lots, fxdaytrader
   return(MathRound(lots/ls)*ls);
}
////////////////////////////////////////////////////////////////////////////////////////

// for 6xx build compatibilità added by milanese


string StringSubstrOld(string x,int a,int b=-1)
{
   if(a<0) a=0; // Stop odd behaviour
   if(b<=0) b=-1; // new MQL4 EOL flag
   return StringSubstr(x,a,b);
}

void TakeChartSnapshot(int ticket, string oc)
{
   //Takes a snapshot of the chart after a trade open or close. Files are stored in the MQL4/Files folder
   //of the platform.

   //--- Prepare a text to show on the chart and a file name.
   //oc is either " open" or " close"
   string name=Symbol() + " ChartScreenShot " + string(ticket) + oc + ".gif";

   //--- Save the chart screenshot in a file in the terminal_directory\MQL4\Files\
   if(ChartScreenShot(0,name, PictureWidth, PictureHeight, ALIGN_RIGHT))
      Alert("Screen snapshot taken ",name);
   //---


}//void TakeChartSnapshot()


bool MopUpTradeClosureFailures()
{
   //Cycle through the ticket numbers in the ForceCloseTickets array, and attempt to close them

   bool Success = true;

   for (int cc = ArraySize(ForceCloseTickets) - 1; cc >= 0; cc--)
   {
      //Order might have closed during a previous attempt, so ensure it is still open.
      if (!BetterOrderSelect(ForceCloseTickets[cc], SELECT_BY_TICKET, MODE_TRADES) )
         continue;

      bool result = CloseOrder(OrderTicket() );
      if (!result)
         Success = false;
   }//for (int cc = ArraySize(ForceCloseTickets) - 1; cc >= 0; cc--)

   if (Success)
      ArrayResize(ForceCloseTickets, 0);

   return(Success);


}//END bool MopUpTradeClosureFailures()

void CalculateLotAsAmountPerCashDollops()
{

   double lotstep = MarketInfo(Symbol(), MODE_LOTSTEP);
   double decimal = 0;
   if (CloseEnough(lotstep, 0.1) )
      decimal = 1;
   if (CloseEnough(lotstep, 0.01) )
      decimal = 2;

   double maxlot = MarketInfo(Symbol(), MODE_MAXLOT);
   double minlot = MarketInfo(Symbol(), MODE_MINLOT);
   double DoshDollop = AccountInfoDouble(ACCOUNT_BALANCE);

   if (UseEquity)
      DoshDollop = AccountInfoDouble(ACCOUNT_EQUITY);


   //Initial lot size
   Lot = NormalizeDouble((DoshDollop / SizeOfDollop) * LotsPerDollopOfCash, decimal);

   //Min/max size check
   if (Lot > maxlot)
      Lot = maxlot;

   if (Lot < minlot)
      Lot = minlot;


}//void CalculateLotAsAmountPerCashDollops()

bool SundayMondayFridayStuff()
{

   //Friday/Saturday stop trading hour
   int d = TimeDayOfWeek(TimeLocal());
   int h = TimeHour(TimeLocal());
   if (d == 5)
      if (h >= FridayStopTradingHour)
         return(false);

   if (d == 4)
      if (!TradeThursdayCandle)
         return(false);


   if (d == 6)
      if (h >= SaturdayStopTradingHour)
         return(false);

   //Sunday candle
   if (d == 0)
      if (!TradeSundayCandle)
         return(false);

   //Monday start hour
   if (d == 1)
      if (h < MondayStartHour)
         return(false);

   //Got this far, so we are in a trading period
   return(true);

}//End bool  SundayMondayFridayStuff()

void TimeToClose()
{
   //Closes all trades if we are at the closing hour

   CloseAllTrades(AllTrades);
   if (ForceTradeClosure)
      CloseAllTrades(AllTrades);

   if (ForceTradeClosure)
      CloseAllTrades(AllTrades);

   if (ForceTradeClosure)
      CloseAllTrades(AllTrades);

}//void ItTimeToClose()

//For OrderSelect() Craptrader documentation states:
//   The pool parameter is ignored if the order is selected by the ticket number. The ticket number is a unique order identifier.
//   To find out from what list the order has been selected, its close time must be analyzed. If the order close time equals to 0,
//   the order is open or pending and taken from the terminal open orders list.
//This function heals this and allows use of pool parameter when selecting orders by ticket number.
//Tomele provided this code. Thanks Thomas.
bool BetterOrderSelect(int index,int select,int pool=-1)
{
   if (select==SELECT_BY_POS)
   {
      if (pool==-1) //No pool given, so take default
         pool=MODE_TRADES;

      return(OrderSelect(index,select,pool));
   }

   if (select==SELECT_BY_TICKET)
   {
      if (pool==-1) //No pool given, so submit as is
         return(OrderSelect(index,select));

      if (pool==MODE_TRADES) //Only return true for existing open trades
         if(OrderSelect(index,select))
            if(OrderCloseTime()==0)
               return(true);

      if (pool==MODE_HISTORY) //Only return true for existing closed trades
         if(OrderSelect(index,select))
            if(OrderCloseTime()>0)
               return(true);
   }

   return(false);
}//End bool BetterOrderSelect(int index,int select,int pool=-1)

//This code by tomele. Thank you Thomas. Wonderful stuff.
bool AreWeAtRollover()
{
   double time;
   int hours,minutes,rstart,rend,ltime;

   time=StrToDouble(RollOverStarts);
   hours=(int)MathFloor(time);
   minutes=(int)MathRound((time-hours)*100);
   rstart=60*hours+minutes;

   time=StrToDouble(RollOverEnds);
   hours=(int)MathFloor(time);
   minutes=(int)MathRound((time-hours)*100);
   rend=60*hours+minutes;

   ltime=TimeHour(TimeCurrent())*60+TimeMinute(TimeCurrent());

   if (rend>rstart)
     if(ltime>rstart && ltime<rend)
       return(true);
   if (rend<rstart) //Over midnight
     if(ltime>rstart || ltime<rend)
       return(true);

   //Got here, so not at rollover
   return(false);

}//End bool AreWeAtRollover()

void LookForBasketClosure()
{

   if (BasketTakeProfitCash > 0)
      if (CashUpl >= BasketTakeProfitCash)
      {
         Alert(WindowExpertName(), " ", Symbol(), " has hit its cash TP. All your trades should have been closed.");
         CloseAllTrades(AllTrades);
         if (ForceTradeClosure)
         {
            CloseAllTrades(AllTrades);
            if (ForceTradeClosure)
            {
               CloseAllTrades(AllTrades);
               if (ForceTradeClosure)
               {
                  return;
               }//if (ForceTradeClosure)
            }//if (ForceTradeClosure)
         }//if (ForceTradeClosure)

      }//if (CashUpl >= BasketTakeProfitCash)

   if (BasketTakeProfitPips > 0)
      if (PipsUpl >= BasketTakeProfitPips)
      {
         Alert(WindowExpertName(), " ", Symbol(), " has hit its pips TP. All your trades should have been closed.");
         CloseAllTrades(AllTrades);
         if (ForceTradeClosure)
         {
            CloseAllTrades(AllTrades);
            if (ForceTradeClosure)
            {
               CloseAllTrades(AllTrades);
               if (ForceTradeClosure)
               {
                  return;
               }//if (ForceTradeClosure)
            }//if (ForceTradeClosure)
         }//if (ForceTradeClosure)

      }//if (PipsUpl >= BasketTakeProfitP)

}//End void LookForBasketClosure()

//+------------------------------------------------------------------+
//| expert start function                                            |
//+------------------------------------------------------------------+
void OnTick()
{
//----
   //int cc;

   //mptm sets a Global Variable when it is closing the trades.
   //This tells this ea not to send any fresh trades.
   if (GlobalVariableCheck(GvName))
      return;
   //'Close all trades this pair only script' sets a GV to tell EA's not to attempt a trade during closure
   if (GlobalVariableCheck(LocalGvName))
      return;
   //'Nuclear option script' sets a GV to tell EA's not to attempt a trade during closure
   if (GlobalVariableCheck(NuclearGvName))
      return;

   //Those stupid sods at MetaCrapper have ensured that stopping an ea by diabling AutoTrading no longer works. Ye Gods alone know why.
   //This routine provided by FxCoder. Thanks Bob.
   if ( !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) )
   {
      Comment("                          TERMINAL AUTOTRADING IS DISABLED");
      return;

   }//if ( !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) )
   if (!IsTradeAllowed() )
   {
      Comment("                          THIS EXPERT HAS LIVE TRADING DISABLED");
      return;
   }//if (!IsTradeAllowed() )

   //In case any trade closures failed
   if (ForceTradeClosure)
   {
      CloseAllTrades(AllTrades);
      return;
   }//if (ArraySize(ForceCloseTickets) > 0)

   if (RemoveExpert)
   {
      ExpertRemove();
      return;
   }//if (RemoveExpert)

   //Session start and open price lines
   if (DrawSessionStartLine || DrawSessionOpenPriceLine)
   {
      static datetime OldSessioStartBarTime = 0;
      if (OldSessioStartBarTime != iTime(Symbol(), TradingTimeFrame, 0))
      {
         OldSessioStartBarTime = iTime(Symbol(), TradingTimeFrame, 0);
         DrawSessionStartLines();
      }//if (OldSessioStartBarTime != iTime(Symbol(), TradingTimeFrame, 0))
   }//if (DrawSessionStartLine || DrawSessionOpenPriceLine)

   //Rollover
   if (DisableEaDuringRollover)
   {
      RolloverInProgress = false;
      if (AreWeAtRollover())
      {
         RolloverInProgress = true;
         DisplayUserFeedback();
         return;
      }//if (AreWeAtRollover)
   }//if (DisableEaDuringRollover)

   //Code to check that there are sufficient bars in the chart's history. Gaheitman provided this. Many thanks George.
   static bool NeedToCheckHistory=false;
   if (NeedToCheckHistory)
   {
        //Customize these for the EA.  You can use externs for the periods
        //if the user can change the timeframes used.
        //In a multi-currency bot, you'd put the calls in a loop across
        //all pairs

        //Customise these to suit what you are doing
        bool WeHaveHistory = true;
        if (!HistoryOK(Symbol(),Period())) WeHaveHistory = false;
        if (!WeHaveHistory)
        {
            Alert("There are <100 bars on this chart so the EA cannot work. It has removed itself. Please refresh your chart.");
            ExpertRemove();
        }//if (!WeHaveHistory)

        //if we get here, history is OK, so stop checking
        NeedToCheckHistory=false;
   }//if (NeedToCheckHistory)

   //Spread calculation
   if (!IsTesting() )
   {
      if(CloseEnough(AverageSpread,0) || RunInSpreadDetectionMode)
      {
         GetAverageSpread();
         ScreenMessage="";
         int left=TicksToCount-CountedTicks;
         //   ************************* added for OBJ_LABEL
         DisplayCount = 1;
         removeAllObjects();
         //   *************************
         SM("Calculating the average spread. "+DoubleToStr(left,0)+" left to count.");
         Comment(ScreenMessage);
         return;
      }//if (CloseEnough(AverageSpread, 0) || RunInSpreadDetectionMode)
      //Keep the average spread updated
      double spread=(Ask-Bid)*factor;
      if(spread>BiggestSpread) BiggestSpread=spread;//Widest spread since the EA was loaded
      static double SpreadTotal=0;
      static int counter=0;
      SpreadTotal+=spread;
      counter++;
      if(counter>=500)
      {
         AverageSpread=NormalizeDouble(SpreadTotal/counter,1);
         //Save the average for restarts.
         GlobalVariableSet(SpreadGvName,AverageSpread);
         SpreadTotal=0;
         counter=0;
      }//if (counter >= 500)
   }//if (!IsTesting() )

   //Create a flashing comment if there has been a rogue trade
   if (RobotSuspended)
   {
      while (RobotSuspended)
      {
         Comment(NL, Gap, "****************** ROBOT SUSPENDED. POSSIBLE ROGUE TRADING ACTIVITY. REMOVE THIE EA IMMEDIATELY ****************** ");
         Sleep(2000);
         Comment("");
         Sleep(1000);
         if ( !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) )
            return;
      }//while (RobotSuspended)
      return;
   }//if (RobotSuspended)

   if(OpenTrades==0)
   {
      TicketNo=-1;
      ForceTradeClosure=false;
   }//if (OrdersTotal() == 0)

   //If HG is sleeping after a trade closure, is it time to awake?
   if(OpenTrades==0 && TooClose()) //TooClose() sets SafetyViolation
   {
      DisplayUserFeedback();
      return;
   }//if (SafetyViolation)

   if(ForceTradeClosure)
   {
      CloseAllTrades(AllTrades);
      return;
   }//if (ForceTradeClosure)

   //Check for a massive spread widening event and pause the ea whilst it is happening
   if (!IsTesting() )
      CheckForSpreadWidening();

   GetSwap(Symbol());//For the swap filters, and in case crim has changed swap rates

   //New candle. Cancel an existing alert sent. By default, all the email stuff is turned off, so this is probably redundant.
   static datetime OldAlertBarsTime;
   if(OldAlertBarsTime!=iTime(NULL,0,0))
   {
      AlertSent=false;
      OldAlertBarsTime=iTime(NULL,0,0);
   }//if (OldAlertBarsTimeBarsTime != iTime(NULL, 0, 0) )

   //Daily results so far - they work on what in in the history tab, so users need warning that
   //what they see displayed on screen depends on that.
   //Code courtesy of TIG yet again. Thanks, George.
   static int OldHistoryTotal;
   if(OrdersHistoryTotal()!=OldHistoryTotal)
   {
      CalculateDailyResult();//Does no harm to have a recalc from time to time
      OldHistoryTotal=OrdersHistoryTotal();
   }//if (OrdersHistoryTotal() != OldHistoryTotal)

   ReadIndicatorValues(); //This might want moving to the trading section at the end of this function if EveryTickMode = false

   //Delete orphaned tp/sl lines
   static int M15Bars;
   if(M15Bars!=iBars(NULL,PERIOD_M15))
   {
      M15Bars=iBars(NULL,PERIOD_M15);
      DeleteOrphanTpSlLines();
   }//if (M15Bars != iBars(NULL, PERIOD_M15)

///////////////////////////////////////////////////////////////////////////////////
   //Find open trades.
   CountOpenTrades();

   //Basket trading
   if (BasketTrading)
   {
      LookForBasketClosure();
         if (ForceTradeClosure)
         {
            CloseAllTrades(AllTrades);
            if (ForceTradeClosure)
            {
               CloseAllTrades(AllTrades);
               if (ForceTradeClosure)
               {
                  return;
               }//if (ForceTradeClosure)
            }//if (ForceTradeClosure)
         }//if (ForceTradeClosure)

   }//if (BasketTrading)

//Safety feature. Sometimes an unexpected concatenation of inputs choice and logic error can cause rapid opening-closing of trades. Detect a closed trade and check that is was not a rogue.
   if(OldOpenTrades!=OpenTrades)
   {
      if(IsClosedTradeRogue())
      {
         RobotSuspended=true;
         return;
      }//if (IsClosedTradeRogue() )
   }//if (OldOpenTrades != OpenTrades)

   OldOpenTrades=OpenTrades;

   //Reset various variables
   if(OpenTrades==0)
   {

   }//if (OpenTrades > 0)

   //Lot size based on account size
   if (!CloseEnough(LotsPerDollopOfCash, 0))
      CalculateLotAsAmountPerCashDollops();

///////////////////////////////////////////////////////////////////////////////////

   //Trading times
   TradeTimeOk=CheckTradingTimes();
   if (TradeTimeOk)
      TradeTimeOk=SundayMondayFridayStuff();
   if(!TradeTimeOk)
   {
      if (OpenTrades > 0)
         if (CloseTradesOutsideTradeTimes)
            TimeToClose();
         DisplayUserFeedback();
         Sleep(1000);
         return;
   }//if (!TradeTimeOk)

///////////////////////////////////////////////////////////////////////////////////

   //Check that there is sufficient margin for trading
   if(!MarginCheck())
   {
      DisplayUserFeedback();
      return;
   }//if (!MarginCheck() )

   //Trading
   if(EveryTickMode) OldBarsTime=0;
   if(OldBarsTime!=iTime(NULL,LookForNewTradeCycle,0))
   {
      OldBarsTime = iTime(NULL, LookForNewTradeCycle, 0);
      //ReadIndicatorValues();//Remember to delete the call higher up in this function if EveryTickMode = false
      if (TimeCurrent() >= TimeToStartTrading)
         if (!StopTrading)
            if (OpenTrades < MaxTradesAllowed)//Un-comment this line for multi traders. Leave commented
                                                //for single traders
            //if (TicketNo == -1)//Comment out this line for multi-traders. Leave uncomment
                               //for single traders
            {
               TimeToStartTrading = 0;//Set to TimeCurrent() + (PostTradeAttemptWaitMinutes * 60) when there is an OrderSend() attempt)
               LookForTradingOpportunities();
            }//if (TicketNo == -1 or if (OpenTrades < MaxTradesAllowed))
   }//if(OldBarsTime!=iTime(NULL,TradingTimeFrame,0))

///////////////////////////////////////////////////////////////////////////////////

   DisplayUserFeedback();

//----
   return;
}
//+------------------------------------------------------------------+
