#!/usr/bin/env python3
"""
OFX Test Data Generator for YMoney
Generates 10 years of fake financial data (2016-2026).
Person grows from $0 to ~$10M across 16 accounts.
Covers all OFX formats (SGML v1 + XML v2), all transaction types,
and a broad set of investment instruments.
"""

import os
import random
from datetime import date, timedelta
from itertools import count

random.seed(42)

BASE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'TestData')
START = date(2016, 1, 1)
END = date(2025, 12, 31)
DTSERVER = '20260101120000[0:GMT]'

_seq = count(1)
def next_fitid(prefix='TXN'):
    return f"{prefix}{next(_seq):08d}"

def dtfmt(d):
    return d.strftime('%Y%m%d') + '120000'

def dtshort(d):
    return d.strftime('%Y%m%d')

def money(amt):
    return f"{amt:.2f}"

# ============================================================================
# SECURITIES DATABASE
# ============================================================================

SECURITIES = {
    # Stocks
    'AAPL':  {'cusip':'037833100','name':'Apple Inc','stype':'stock','stocktype':'COMMON'},
    'MSFT':  {'cusip':'594918104','name':'Microsoft Corp','stype':'stock','stocktype':'COMMON'},
    'NVDA':  {'cusip':'67066G104','name':'NVIDIA Corp','stype':'stock','stocktype':'COMMON'},
    'AMZN':  {'cusip':'023135106','name':'Amazon.com Inc','stype':'stock','stocktype':'COMMON'},
    'GOOGL': {'cusip':'02079K305','name':'Alphabet Inc Cl A','stype':'stock','stocktype':'COMMON'},
    'TSLA':  {'cusip':'88160R101','name':'Tesla Inc','stype':'stock','stocktype':'COMMON'},
    'JPM':   {'cusip':'46625H100','name':'JPMorgan Chase & Co','stype':'stock','stocktype':'COMMON'},
    'V':     {'cusip':'92826C839','name':'Visa Inc Cl A','stype':'stock','stocktype':'COMMON'},
    'JNJ':   {'cusip':'478160104','name':'Johnson & Johnson','stype':'stock','stocktype':'COMMON'},
    'BRKB':  {'cusip':'084670702','name':'Berkshire Hathaway Cl B','stype':'stock','stocktype':'COMMON'},
    # ETFs (reported as STOCKINFO in OFX)
    'SPY':   {'cusip':'78462F103','name':'SPDR S&P 500 ETF Trust','stype':'stock','stocktype':'COMMON'},
    'QQQ':   {'cusip':'46090E103','name':'Invesco QQQ Trust','stype':'stock','stocktype':'COMMON'},
    'VTI':   {'cusip':'922908769','name':'Vanguard Total Stock Market ETF','stype':'stock','stocktype':'COMMON'},
    'VXUS':  {'cusip':'921909768','name':'Vanguard Total Intl Stock ETF','stype':'stock','stocktype':'COMMON'},
    'BND':   {'cusip':'921937835','name':'Vanguard Total Bond Market ETF','stype':'stock','stocktype':'COMMON'},
    'GLD':   {'cusip':'78463V107','name':'SPDR Gold Shares','stype':'stock','stocktype':'COMMON'},
    'ARKK':  {'cusip':'00214Q104','name':'ARK Innovation ETF','stype':'stock','stocktype':'COMMON'},
    # Mutual Funds
    'VFIAX': {'cusip':'922908363','name':'Vanguard 500 Index Fund Admiral','stype':'mf','mftype':'OPENEND'},
    'FXAIX': {'cusip':'315911750','name':'Fidelity 500 Index Fund','stype':'mf','mftype':'OPENEND'},
    'VBTLX': {'cusip':'921937843','name':'Vanguard Total Bond Market Index Admiral','stype':'mf','mftype':'OPENEND'},
    'SWPPX': {'cusip':'808509863','name':'Schwab S&P 500 Index Fund','stype':'mf','mftype':'OPENEND'},
    'DODGX': {'cusip':'256219106','name':'Dodge & Cox Stock Fund','stype':'mf','mftype':'OPENEND'},
    'VTIVX': {'cusip':'92202E102','name':'Vanguard Target Retirement 2045','stype':'mf','mftype':'OPENEND'},
    'FCNTX': {'cusip':'316071109','name':'Fidelity Contrafund','stype':'mf','mftype':'OPENEND'},
    # Bonds
    'UST10Y':{'cusip':'91282CJL6','name':'US Treasury Note 3.5% 2033','stype':'debt','debttype':'COUPON','parvalue':1000,'couponrt':3.5,'couponfreq':'SEMIANNUAL','dtmat':'20331115'},
    'UST2Y': {'cusip':'91282CKV2','name':'US Treasury Note 4.25% 2026','stype':'debt','debttype':'COUPON','parvalue':1000,'couponrt':4.25,'couponfreq':'SEMIANNUAL','dtmat':'20260930'},
    'AAPLBD':{'cusip':'037833DV0','name':'Apple Inc 2.65% 2030','stype':'debt','debttype':'COUPON','parvalue':1000,'couponrt':2.65,'couponfreq':'SEMIANNUAL','dtmat':'20300501'},
    'MSFTBD':{'cusip':'594918BW3','name':'Microsoft Corp 2.4% 2027','stype':'debt','debttype':'COUPON','parvalue':1000,'couponrt':2.4,'couponfreq':'SEMIANNUAL','dtmat':'20270806'},
    'CAMUBD':{'cusip':'13063DAA9','name':'California State GO 3.0% 2028','stype':'debt','debttype':'COUPON','parvalue':5000,'couponrt':3.0,'couponfreq':'SEMIANNUAL','dtmat':'20281201'},
    # Options
    'AAPL_C200_260116':{'cusip':'0AAPL.AB60116200','name':'AAPL Jan 16 2026 200 Call','stype':'opt','opttype':'CALL','strikeprice':200,'dtexpire':'20260116','shperctrct':100,'underlying':'037833100'},
    'NVDA_C500_260320':{'cusip':'0NVDA.CF60320500','name':'NVDA Mar 20 2026 500 Call','stype':'opt','opttype':'CALL','strikeprice':500,'dtexpire':'20260320','shperctrct':100,'underlying':'67066G104'},
    'SPY_P400_250620': {'cusip':'0SPY..RE50620400','name':'SPY Jun 20 2025 400 Put','stype':'opt','opttype':'PUT','strikeprice':400,'dtexpire':'20250620','shperctrct':100,'underlying':'78462F103'},
    'TSLA_P250_251219':{'cusip':'0TSLA.XE51219250','name':'TSLA Dec 19 2025 250 Put','stype':'opt','opttype':'PUT','strikeprice':250,'dtexpire':'20251219','shperctrct':100,'underlying':'88160R101'},
    'AMZN_C200_250919':{'cusip':'0AMZN.IB50919200','name':'AMZN Sep 19 2025 200 Call','stype':'opt','opttype':'CALL','strikeprice':200,'dtexpire':'20250919','shperctrct':100,'underlying':'023135106'},
    # Futures (OTHERINFO)
    'ES':  {'cusip':'ES2603H6','name':'E-mini S&P 500 Mar 2026','stype':'other','typedesc':'Futures Contract'},
    'NQ':  {'cusip':'NQ2603H6','name':'E-mini Nasdaq 100 Mar 2026','stype':'other','typedesc':'Futures Contract'},
    'GC':  {'cusip':'GC2604J6','name':'Gold Futures Apr 2026','stype':'other','typedesc':'Futures Contract'},
    'CL':  {'cusip':'CL2605K6','name':'Crude Oil Futures May 2026','stype':'other','typedesc':'Futures Contract'},
    # Crypto (OTHERINFO)
    'BTC': {'cusip':'BTC0000001','name':'Bitcoin','stype':'other','typedesc':'Cryptocurrency'},
    'ETH': {'cusip':'ETH0000001','name':'Ethereum','stype':'other','typedesc':'Cryptocurrency'},
    'SOL': {'cusip':'SOL0000001','name':'Solana','stype':'other','typedesc':'Cryptocurrency'},
}

# ============================================================================
# ACCOUNT DEFINITIONS
# ============================================================================

BANK_ACCTS = [
    {'id':'chase-checking','name':'Chase Total Checking','bankid':'021000021','acctid':'9876543210','accttype':'CHECKING','org':'Chase','fid':'10898','start':date(2016,1,1)},
    {'id':'marcus-savings','name':'Marcus Online Savings','bankid':'124085024','acctid':'1234567890','accttype':'SAVINGS','org':'Marcus by Goldman Sachs','fid':'15208','start':date(2016,3,1)},
    {'id':'fidelity-mma','name':'Fidelity Cash Management','bankid':'101205681','acctid':'Z12345678','accttype':'MONEYMRKT','org':'Fidelity','fid':'7776','start':date(2020,1,1)},
    {'id':'ally-cd','name':'Ally 12-Month High Yield CD','bankid':'124003116','acctid':'8765432109','accttype':'CD','org':'Ally Bank','fid':'11288','start':date(2022,6,1)},
]

CC_ACCTS = [
    {'id':'chase-sapphire','name':'Chase Sapphire Reserve','acctid':'4266841234567890','org':'Chase','fid':'10898','start':date(2016,1,1)},
    {'id':'amex-platinum','name':'American Express Platinum','acctid':'379912345678901','org':'American Express','fid':'3101','start':date(2017,6,1)},
    {'id':'citi-doublecash','name':'Citi Double Cash Card','acctid':'5423001234567890','org':'Citibank','fid':'24909','start':date(2018,3,1)},
    {'id':'capitalone-venture','name':'Capital One Venture X','acctid':'4147201234567890','org':'Capital One','fid':'31312','start':date(2019,1,1)},
    {'id':'discover-it','name':'Discover it Cash Back','acctid':'6011001234567890','org':'Discover','fid':'7101','start':date(2019,9,1)},
]

BROKERAGE_ACCTS = [
    {'id':'fidelity-brokerage','name':'Fidelity Individual','brokerid':'fidelity.com','acctid':'X12345678','org':'Fidelity','fid':'7776','start':date(2018,1,1)},
    {'id':'schwab-taxable','name':'Schwab Taxable','brokerid':'schwab.com','acctid':'78901234','org':'Charles Schwab','fid':'5104','start':date(2019,6,1)},
    {'id':'ibkr-margin','name':'Interactive Brokers Margin','brokerid':'interactivebrokers.com','acctid':'U9876543','org':'Interactive Brokers','fid':'4705','start':date(2021,3,1)},
]

RETIREMENT_ACCTS = [
    {'id':'fidelity-401k','name':'Fidelity 401k TechCorp','brokerid':'fidelity.com','acctid':'K12345678','org':'Fidelity','fid':'7776','start':date(2016,1,1),'end':date(2020,3,31)},
    {'id':'vanguard-401k','name':'Vanguard 401k MegaSoft','brokerid':'vanguard.com','acctid':'87654321','org':'Vanguard','fid':'15103','start':date(2020,4,1),'end':date(2023,6,30)},
    {'id':'schwab-401k','name':'Schwab 401k DataFlow','brokerid':'schwab.com','acctid':'R12345678','org':'Charles Schwab','fid':'5104','start':date(2023,7,1),'end':None},
    {'id':'fidelity-rollover','name':'Fidelity Rollover IRA','brokerid':'fidelity.com','acctid':'R98765432','org':'Fidelity','fid':'7776','start':date(2020,5,1),'end':None},
]

# ============================================================================
# OFX FORMATTING HELPERS
# ============================================================================

def _esc(val):
    """Escape XML special characters in a value."""
    s = str(val)
    s = s.replace('&', '&amp;')
    s = s.replace('<', '&lt;')
    s = s.replace('>', '&gt;')
    return s

def E(tag, val, fmt):
    """Leaf element."""
    if fmt == 'sgml':
        return f"<{tag}>{val}"
    return f"<{tag}>{_esc(val)}</{tag}>"

def ofx_header(fmt):
    if fmt == 'sgml':
        return ("OFXHEADER:100\nDATA:OFXSGML\nVERSION:102\nSECURITY:NONE\n"
                "ENCODING:USASCII\nCHARSET:1252\nCOMPRESSION:NONE\n"
                "OLDFILEUID:NONE\nNEWFILEUID:NONE\n\n")
    return ('<?xml version="1.0" encoding="UTF-8"?>\n'
            '<?OFX OFXHEADER="200" VERSION="220" SECURITY="NONE" '
            'OLDFILEUID="NONE" NEWFILEUID="NONE"?>\n\n')

def signon(org, fid, fmt):
    return '\n'.join([
        '<SIGNONMSGSRSV1>','<SONRS>','<STATUS>',
        E('CODE','0',fmt), E('SEVERITY','INFO',fmt),
        '</STATUS>', E('DTSERVER',DTSERVER,fmt), E('LANGUAGE','ENG',fmt),
        '<FI>', E('ORG',org,fmt), E('FID',fid,fmt), '</FI>',
        '</SONRS>','</SIGNONMSGSRSV1>',
    ])

def secid_block(cusip, fmt):
    return '\n'.join(['<SECID>', E('UNIQUEID',cusip,fmt), E('UNIQUEIDTYPE','CUSIP',fmt), '</SECID>'])

def status_ok(fmt):
    return '\n'.join(['<STATUS>', E('CODE','0',fmt), E('SEVERITY','INFO',fmt), '</STATUS>'])

# ============================================================================
# BANK TRANSACTION GENERATORS
# ============================================================================

def gen_bank_txns(acct, fmt):
    """Generate all bank transactions for an account over its lifetime."""
    lines = []
    d = acct['start']
    end = END
    bal = 0.0

    # Salary schedule (grows over years)
    def biweekly_salary(yr):
        base = {2016:1600,2017:1900,2018:2400,2019:2900,2020:4000,
                2021:4600,2022:5500,2023:6700,2024:8500,2025:9200}
        return base.get(yr, 3000)

    txn_type_map = {
        'CHECKING': _gen_checking_txns,
        'SAVINGS': _gen_savings_txns,
        'MONEYMRKT': _gen_mma_txns,
        'CD': _gen_cd_txns,
    }

    txns = txn_type_map[acct['accttype']](acct, fmt)
    # Calculate running balance
    bal = sum(t['amount'] for t in txns)

    stmtlines = []
    for t in txns:
        stmtlines.append('<STMTTRN>')
        stmtlines.append(E('TRNTYPE', t['trntype'], fmt))
        stmtlines.append(E('DTPOSTED', dtfmt(t['date']), fmt))
        if t.get('dtuser'):
            stmtlines.append(E('DTUSER', dtfmt(t['dtuser']), fmt))
        stmtlines.append(E('TRNAMT', money(t['amount']), fmt))
        stmtlines.append(E('FITID', t['fitid'], fmt))
        if t.get('checknum'):
            stmtlines.append(E('CHECKNUM', t['checknum'], fmt))
        if t.get('refnum'):
            stmtlines.append(E('REFNUM', t['refnum'], fmt))
        if t.get('sic'):
            stmtlines.append(E('SIC', t['sic'], fmt))
        stmtlines.append(E('NAME', t['name'], fmt))
        if t.get('memo'):
            stmtlines.append(E('MEMO', t['memo'], fmt))
        stmtlines.append('</STMTTRN>')

    return '\n'.join([
        '<BANKMSGSRSV1>','<STMTTRNRS>',
        E('TRNUID', next_fitid('BTUID'), fmt),
        status_ok(fmt),
        '<STMTRS>',
        E('CURDEF','USD',fmt),
        '<BANKACCTFROM>',
        E('BANKID',acct['bankid'],fmt),
        E('ACCTID',acct['acctid'],fmt),
        E('ACCTTYPE',acct['accttype'],fmt),
        '</BANKACCTFROM>',
        '<BANKTRANLIST>',
        E('DTSTART',dtfmt(acct['start']),fmt),
        E('DTEND',dtfmt(END),fmt),
        '\n'.join(stmtlines),
        '</BANKTRANLIST>',
        '<LEDGERBAL>',
        E('BALAMT',money(bal),fmt),
        E('DTASOF',dtfmt(END),fmt),
        '</LEDGERBAL>',
        '<AVAILBAL>',
        E('BALAMT',money(bal - 50),fmt),
        E('DTASOF',dtfmt(END),fmt),
        '</AVAILBAL>',
        '</STMTRS>','</STMTTRNRS>','</BANKMSGSRSV1>',
    ]), bal

def _biweekly_dates(start, end):
    """Generate biweekly (every other Friday) dates."""
    d = start
    while d.weekday() != 4:  # Find first Friday
        d += timedelta(days=1)
    while d <= end:
        yield d
        d += timedelta(days=14)

def _monthly_dates(start, end, day=1):
    """Generate monthly dates."""
    d = start.replace(day=min(day, 28))
    while d <= end:
        if d >= start:
            yield d
        if d.month == 12:
            d = d.replace(year=d.year+1, month=1)
        else:
            d = d.replace(month=d.month+1)

def _gen_checking_txns(acct, fmt):
    txns = []
    start = acct['start']

    # All TRNTYPE values we need to cover
    salary_base = {2016:1600,2017:1900,2018:2400,2019:2900,2020:4000,
                   2021:4600,2022:5500,2023:6700,2024:8500,2025:9200}

    # DIRECTDEP - Bi-weekly payroll
    for d in _biweekly_dates(start, END):
        amt = salary_base.get(d.year, 3000) + random.uniform(-50, 50)
        txns.append({'trntype':'DIRECTDEP','date':d,'amount':round(amt,2),
                     'fitid':next_fitid('DD'),'name':'TECHCORP INC PAYROLL',
                     'memo':'Direct Deposit - Salary'})

    # CHECK - Rent (monthly, years 2016-2019), then mortgage
    for d in _monthly_dates(start, END, day=1):
        amt = -1800 if d.year < 2020 else -3200
        txns.append({'trntype':'CHECK','date':d,'amount':round(amt,2),
                     'fitid':next_fitid('CK'),'name':'RENT PAYMENT' if d.year < 2020 else 'MORTGAGE PMT',
                     'checknum':str(1000+len(txns)),'memo':'Housing payment'})

    # XFER - Transfer to savings (monthly)
    for d in _monthly_dates(start, END, day=5):
        amt = -(200 + d.year * 50 - 2016 * 50 + random.randint(0, 200))
        txns.append({'trntype':'XFER','date':d,'amount':round(amt,2),
                     'fitid':next_fitid('XF'),'name':'Online Transfer to SAV',
                     'memo':'Transfer to savings'})

    # DIRECTDEBIT - Utilities (monthly)
    utils = [
        ('Electric Company', -80, -200, '4911'),
        ('Gas Utility Co', -40, -120, '4924'),
        ('Water & Sewer', -30, -60, '4941'),
        ('Internet Provider', -79.99, -79.99, '4813'),
        ('Cell Phone Bill', -85, -85, '4812'),
    ]
    for name, lo, hi, sic in utils:
        for d in _monthly_dates(start, END, day=random.randint(10,20)):
            amt = round(random.uniform(lo, hi), 2)
            txns.append({'trntype':'DIRECTDEBIT','date':d,'amount':amt,
                         'fitid':next_fitid('DB'),'name':name,'sic':sic,
                         'memo':'Auto-pay'})

    # ATM - Cash withdrawals (2-3 per month)
    d = start
    while d <= END:
        for _ in range(random.randint(1, 3)):
            wd = d + timedelta(days=random.randint(0, 27))
            if wd <= END and wd >= start:
                amt = -random.choice([40, 60, 80, 100, 200])
                txns.append({'trntype':'ATM','date':wd,'amount':float(amt),
                             'fitid':next_fitid('AT'),'name':'ATM WITHDRAWAL',
                             'memo':'Non-Chase ATM' if random.random()<0.3 else 'Chase ATM'})
        d = (d.replace(day=28) + timedelta(days=4)).replace(day=1)

    # POS - Point of sale purchases (5-10 per month)
    pos_merchants = ['WHOLE FOODS','TARGET','COSTCO','WALMART','HOME DEPOT',
                     'GAS STATION','PHARMACY CVS','TRADER JOES','SAFEWAY',
                     'STARBUCKS','CHIPOTLE','SUBWAY']
    d = start
    while d <= END:
        for _ in range(random.randint(4, 10)):
            pd = d + timedelta(days=random.randint(0, 27))
            if pd <= END and pd >= start:
                amt = -round(random.uniform(5, 250), 2)
                txns.append({'trntype':'POS','date':pd,'amount':amt,
                             'fitid':next_fitid('PS'),'name':random.choice(pos_merchants),
                             'sic':'5411','memo':'Debit card purchase'})
        d = (d.replace(day=28) + timedelta(days=4)).replace(day=1)

    # DEP - Cash/check deposits (occasional)
    for d in _monthly_dates(start, END, day=15):
        if random.random() < 0.15:
            amt = round(random.uniform(50, 2000), 2)
            txns.append({'trntype':'DEP','date':d,'amount':amt,
                         'fitid':next_fitid('DP'),'name':'CHECK DEPOSIT',
                         'memo':'Mobile deposit'})

    # PAYMENT - Bill payments
    for d in _monthly_dates(start, END, day=25):
        if random.random() < 0.3:
            amt = -round(random.uniform(50, 500), 2)
            txns.append({'trntype':'PAYMENT','date':d,'amount':amt,
                         'fitid':next_fitid('PM'),'name':'ONLINE BILL PAYMENT',
                         'memo':'Bill pay'})

    # INT - Monthly interest credit
    for d in _monthly_dates(start, END, day=28):
        amt = round(random.uniform(0.01, 2.50), 2)
        txns.append({'trntype':'INT','date':d,'amount':amt,
                     'fitid':next_fitid('IN'),'name':'INTEREST PAYMENT',
                     'memo':'Monthly interest'})

    # FEE - Occasional bank fees
    for d in _monthly_dates(start, END, day=28):
        if random.random() < 0.05:
            txns.append({'trntype':'FEE','date':d,'amount':-12.00,
                         'fitid':next_fitid('FE'),'name':'MONTHLY SERVICE FEE',
                         'memo':'Account maintenance fee'})

    # SRVCHG - Wire transfer fee (rare)
    for d in _monthly_dates(start, END, day=15):
        if random.random() < 0.02:
            txns.append({'trntype':'SRVCHG','date':d,'amount':-25.00,
                         'fitid':next_fitid('SC'),'name':'WIRE TRANSFER FEE',
                         'memo':'Outgoing domestic wire'})

    # REPEATPMT - Recurring subscription
    for d in _monthly_dates(date(2018,1,1) if start < date(2018,1,1) else start, END, day=7):
        txns.append({'trntype':'REPEATPMT','date':d,'amount':-15.99,
                     'fitid':next_fitid('RP'),'name':'STREAMING SERVICE',
                     'memo':'Monthly subscription'})

    # CREDIT - Misc credits (refunds, etc.)
    for d in _monthly_dates(start, END, day=20):
        if random.random() < 0.1:
            amt = round(random.uniform(10, 200), 2)
            txns.append({'trntype':'CREDIT','date':d,'amount':amt,
                         'fitid':next_fitid('CR'),'name':'MERCHANT REFUND',
                         'memo':'Purchase return'})

    # DEBIT - Misc debits
    for d in _monthly_dates(start, END, day=12):
        if random.random() < 0.1:
            amt = -round(random.uniform(20, 300), 2)
            txns.append({'trntype':'DEBIT','date':d,'amount':amt,
                         'fitid':next_fitid('DT'),'name':'DEBIT TRANSACTION',
                         'memo':'Misc debit'})

    # CASH - Cash advance (very rare)
    if random.random() < 0.3:
        cd = start + timedelta(days=random.randint(100, 3000))
        if cd <= END:
            txns.append({'trntype':'CASH','date':cd,'amount':-500.00,
                         'fitid':next_fitid('CA'),'name':'CASH ADVANCE',
                         'memo':'Emergency cash'})

    # OTHER - Miscellaneous
    for yr in range(2016, 2026):
        if random.random() < 0.2:
            d = date(yr, random.randint(1,12), random.randint(1,28))
            txns.append({'trntype':'OTHER','date':d,'amount':round(random.uniform(-100,100),2),
                         'fitid':next_fitid('OT'),'name':'MISC ADJUSTMENT',
                         'memo':'Bank adjustment'})

    # Large bonus deposits in later years
    for yr in range(2021, 2026):
        bonus_d = date(yr, 3, 15)
        bonus = {2021:15000,2022:25000,2023:40000,2024:60000,2025:80000}[yr]
        txns.append({'trntype':'DIRECTDEP','date':bonus_d,'amount':float(bonus),
                     'fitid':next_fitid('BN'),'name':'TECHCORP INC BONUS',
                     'memo':'Annual performance bonus'})

    txns.sort(key=lambda t: t['date'])
    return txns


def _gen_savings_txns(acct, fmt):
    txns = []
    start = acct['start']
    # Transfers in from checking (monthly)
    for d in _monthly_dates(start, END, day=6):
        amt = 200 + (d.year - 2016) * 50 + random.randint(0, 200)
        txns.append({'trntype':'XFER','date':d,'amount':round(amt,2),
                     'fitid':next_fitid('XF'),'name':'Transfer from Checking',
                     'memo':'Savings transfer'})
    # Interest (monthly, growing with balance)
    running = 0.0
    for d in _monthly_dates(start, END, day=28):
        interest = max(0.01, running * 0.004 / 12)  # ~4% APY approximation
        txns_before = [t for t in txns if t['date'] <= d]
        running = sum(t['amount'] for t in txns_before)
        interest = max(0.01, running * 0.004 / 12)
        txns.append({'trntype':'INT','date':d,'amount':round(interest,2),
                     'fitid':next_fitid('IN'),'name':'INTEREST PAYMENT',
                     'memo':'Monthly interest earned'})
    # Occasional large deposits
    for yr in range(2020, 2026):
        d = date(yr, 6, 15)
        txns.append({'trntype':'DEP','date':d,'amount':round(random.uniform(5000, 20000),2),
                     'fitid':next_fitid('DP'),'name':'LARGE DEPOSIT',
                     'memo':'Savings boost'})
    # DIV - Dividend credit (rare for savings, but covers the type)
    for yr in range(2022, 2026):
        d = date(yr, 12, 31)
        txns.append({'trntype':'DIV','date':d,'amount':round(random.uniform(10,50),2),
                     'fitid':next_fitid('DV'),'name':'ANNUAL DIVIDEND',
                     'memo':'Loyalty bonus'})
    txns.sort(key=lambda t: t['date'])
    return txns


def _gen_mma_txns(acct, fmt):
    txns = []
    start = acct['start']
    # Initial deposit
    txns.append({'trntype':'XFER','date':start,'amount':50000.00,
                 'fitid':next_fitid('XF'),'name':'Transfer from Checking',
                 'memo':'Initial money market deposit'})
    # Monthly interest
    for d in _monthly_dates(start, END, day=28):
        txns.append({'trntype':'INT','date':d,'amount':round(random.uniform(50, 400),2),
                     'fitid':next_fitid('IN'),'name':'INTEREST EARNED',
                     'memo':'Money market interest'})
    # Periodic additional deposits
    for d in _monthly_dates(start, END, day=10):
        if random.random() < 0.3:
            txns.append({'trntype':'XFER','date':d,'amount':round(random.uniform(2000, 10000),2),
                         'fitid':next_fitid('XF'),'name':'Transfer from Checking',
                         'memo':'Additional deposit'})
    txns.sort(key=lambda t: t['date'])
    return txns


def _gen_cd_txns(acct, fmt):
    txns = []
    start = acct['start']
    # Initial CD purchase
    txns.append({'trntype':'DEP','date':start,'amount':25000.00,
                 'fitid':next_fitid('DP'),'name':'CD PURCHASE',
                 'memo':'12-Month CD at 4.5% APY'})
    # Monthly interest
    for d in _monthly_dates(start, END, day=28):
        txns.append({'trntype':'INT','date':d,'amount':round(25000 * 0.045 / 12, 2),
                     'fitid':next_fitid('IN'),'name':'CD INTEREST',
                     'memo':'Certificate of Deposit interest'})
    # Renewal deposits
    for yr in range(2023, 2026):
        d = date(yr, 6, 1)
        txns.append({'trntype':'DEP','date':d,'amount':25000.00,
                     'fitid':next_fitid('DP'),'name':'CD RENEWAL DEPOSIT',
                     'memo':'CD rollover and additional deposit'})
    txns.sort(key=lambda t: t['date'])
    return txns


# ============================================================================
# CREDIT CARD TRANSACTION GENERATORS
# ============================================================================

def gen_cc_txns(acct, fmt):
    txns = []
    start = acct['start']

    merchants = [
        ('AMAZON.COM','5942','Online shopping'),('UBER','4121','Rideshare'),
        ('UBER EATS','5812','Food delivery'),('DOORDASH','5812','Food delivery'),
        ('NETFLIX','4899','Streaming'),('SPOTIFY','7922','Music streaming'),
        ('DELTA AIRLINES','4511','Air travel'),('MARRIOTT HOTEL','7011','Lodging'),
        ('HERTZ CAR RENTAL','7512','Car rental'),('SHELL OIL','5541','Gas station'),
        ('CHEVRON','5541','Gas station'),('WHOLE FOODS MKT','5411','Grocery'),
        ('TRADER JOES','5411','Grocery'),('BEST BUY','5732','Electronics'),
        ('APPLE STORE','5732','Electronics'),('NORDSTROM','5651','Clothing'),
        ('WALGREENS','5912','Pharmacy'),('STARBUCKS','5814','Coffee'),
        ('RESTAURANT XYZ','5812','Dining'),('DRY CLEANER','7210','Laundry'),
        ('GYM MEMBERSHIP','7941','Fitness'),('DOCTOR OFFICE','8011','Medical'),
        ('DENTAL CARE','8021','Dental'),('AUTO MECHANIC','7538','Car repair'),
        ('PARKING GARAGE','7521','Parking'),('TOLL AUTHORITY','4784','Toll'),
    ]

    d = start
    while d <= END:
        # 10-25 purchases per month
        for _ in range(random.randint(10, 25)):
            pd = d + timedelta(days=random.randint(0, 27))
            if pd > END or pd < start:
                continue
            merch, sic, memo = random.choice(merchants)
            amt = -round(random.uniform(3, 500), 2)
            # Occasional big purchases
            if random.random() < 0.05:
                amt = -round(random.uniform(500, 5000), 2)
            txns.append({'trntype':'DEBIT','date':pd,'amount':amt,
                         'fitid':next_fitid('CC'),'name':merch,'sic':sic,'memo':memo})

        # Monthly payment (CREDIT)
        pay_d = d + timedelta(days=25)
        if pay_d <= END:
            month_charges = sum(t['amount'] for t in txns if t['date'].month == d.month and t['date'].year == d.year and t['amount'] < 0)
            payment = -month_charges * random.uniform(0.8, 1.0)
            txns.append({'trntype':'CREDIT','date':pay_d,'amount':round(payment,2),
                         'fitid':next_fitid('CP'),'name':'PAYMENT THANK YOU',
                         'memo':'Online payment received'})

        # Interest charge (if not fully paid)
        if random.random() < 0.2:
            int_d = d + timedelta(days=28)
            if int_d <= END:
                txns.append({'trntype':'INT','date':int_d,'amount':-round(random.uniform(5,100),2),
                             'fitid':next_fitid('FI'),'name':'INTEREST CHARGE',
                             'memo':'Purchase interest charge'})

        # FEE - Annual fee (once per year)
        if d.month == 1:
            fee = {'chase-sapphire':-550,'amex-platinum':-695,'citi-doublecash':0,
                   'capitalone-venture':-395,'discover-it':0}.get(acct['id'], 0)
            if fee != 0:
                txns.append({'trntype':'FEE','date':d,'amount':float(fee),
                             'fitid':next_fitid('AF'),'name':'ANNUAL MEMBERSHIP FEE',
                             'memo':'Card annual fee'})

        # SRVCHG - Late fee (very rare)
        if random.random() < 0.02:
            txns.append({'trntype':'SRVCHG','date':d+timedelta(days=20),
                         'amount':-39.00,'fitid':next_fitid('LF'),
                         'name':'LATE PAYMENT FEE','memo':'Late payment penalty'})

        # Cash back / rewards credit (quarterly for some cards)
        if d.month in (3,6,9,12) and acct['id'] in ('citi-doublecash','discover-it'):
            txns.append({'trntype':'CREDIT','date':d+timedelta(days=15),
                         'amount':round(random.uniform(20,150),2),
                         'fitid':next_fitid('RW'),'name':'CASH BACK REWARD',
                         'memo':'Statement credit rewards'})

        # Advance to next month
        if d.month == 12:
            d = d.replace(year=d.year+1, month=1)
        else:
            d = d.replace(month=d.month+1)

    txns.sort(key=lambda t: t['date'])
    bal = sum(t['amount'] for t in txns)
    return txns, bal

def format_cc_stmt(acct, txns, bal, fmt):
    stmtlines = []
    for t in txns:
        stmtlines.append('<STMTTRN>')
        stmtlines.append(E('TRNTYPE', t['trntype'], fmt))
        stmtlines.append(E('DTPOSTED', dtfmt(t['date']), fmt))
        stmtlines.append(E('TRNAMT', money(t['amount']), fmt))
        stmtlines.append(E('FITID', t['fitid'], fmt))
        if t.get('sic'):
            stmtlines.append(E('SIC', t['sic'], fmt))
        stmtlines.append(E('NAME', t['name'], fmt))
        if t.get('memo'):
            stmtlines.append(E('MEMO', t['memo'], fmt))
        stmtlines.append('</STMTTRN>')

    return '\n'.join([
        '<CREDITCARDMSGSRSV1>','<CCSTMTTRNRS>',
        E('TRNUID', next_fitid('CTUID'), fmt), status_ok(fmt),
        '<CCSTMTRS>', E('CURDEF','USD',fmt),
        '<CCACCTFROM>', E('ACCTID',acct['acctid'],fmt), '</CCACCTFROM>',
        '<BANKTRANLIST>',
        E('DTSTART',dtfmt(acct['start']),fmt),
        E('DTEND',dtfmt(END),fmt),
        '\n'.join(stmtlines),
        '</BANKTRANLIST>',
        '<LEDGERBAL>', E('BALAMT',money(bal),fmt), E('DTASOF',dtfmt(END),fmt), '</LEDGERBAL>',
        '<AVAILBAL>', E('BALAMT',money(max(0,-bal+15000)),fmt), E('DTASOF',dtfmt(END),fmt), '</AVAILBAL>',
        '</CCSTMTRS>','</CCSTMTTRNRS>','</CREDITCARDMSGSRSV1>',
    ])


# ============================================================================
# INVESTMENT TRANSACTION GENERATORS
# ============================================================================

def gen_inv_txns_brokerage(acct, fmt):
    """Generate brokerage account transactions covering all inv txn types."""
    txns = []
    start = acct['start']
    end_d = END
    used_secs = set()

    # INVBANKTRAN - Cash deposits into the account
    for d in _monthly_dates(start, end_d, day=3):
        amt = round(random.uniform(1000, 8000) * (1 + (d.year - 2016) * 0.3), 2)
        txns.append({'type':'INVBANKTRAN','date':d,'amount':amt,
                     'trntype':'XFER','name':'ACH DEPOSIT','fitid':next_fitid('IB'),
                     'subacctfund':'CASH'})

    stocks = ['AAPL','MSFT','NVDA','AMZN','GOOGL','TSLA','JPM','V','JNJ','BRKB']
    etfs = ['SPY','QQQ','VTI','VXUS','BND','GLD','ARKK']
    bonds = ['UST10Y','UST2Y','AAPLBD','MSFTBD','CAMUBD']
    options = ['AAPL_C200_260116','NVDA_C500_260320','SPY_P400_250620','TSLA_P250_251219','AMZN_C200_250919']
    futures = ['ES','NQ','GC','CL']
    crypto = ['BTC','ETH','SOL']

    # BUYSTOCK - Regular stock purchases
    for d in _monthly_dates(start, end_d, day=random.randint(5,15)):
        ticker = random.choice(stocks + etfs)
        used_secs.add(ticker)
        units = round(random.uniform(1, 50), 4)
        price = _fake_price(ticker, d)
        total = -round(units * price + random.uniform(0, 7), 2)  # including commission
        commission = round(random.uniform(0, 4.95), 2)
        txns.append({'type':'BUYSTOCK','date':d,'ticker':ticker,
                     'units':units,'unitprice':price,'total':total,
                     'commission':commission,'fitid':next_fitid('BS'),
                     'subacctsec':'CASH','subacctfund':'CASH','buytype':'BUY'})

    # SELLSTOCK - Occasional sells
    for d in _monthly_dates(start, end_d, day=20):
        if random.random() < 0.25:
            ticker = random.choice(stocks + etfs)
            used_secs.add(ticker)
            units = round(random.uniform(1, 20), 4)
            price = _fake_price(ticker, d)
            total = round(units * price - random.uniform(0, 7), 2)
            txns.append({'type':'SELLSTOCK','date':d,'ticker':ticker,
                         'units':units,'unitprice':price,'total':total,
                         'commission':round(random.uniform(0,4.95),2),
                         'fitid':next_fitid('SS'),
                         'subacctsec':'CASH','subacctfund':'CASH','selltype':'SELL'})

    # SELLSTOCK short sell + BUYSTOCK buy to cover (IBKR margin account)
    if 'ibkr' in acct['id']:
        for yr in range(max(2022, start.year), 2026):
            d = date(yr, random.randint(1,6), 15)
            ticker = random.choice(['TSLA','ARKK','AMZN'])
            used_secs.add(ticker)
            units = round(random.uniform(5, 30), 4)
            price = _fake_price(ticker, d)
            txns.append({'type':'SELLSTOCK','date':d,'ticker':ticker,
                         'units':units,'unitprice':price,
                         'total':round(units*price,2),
                         'commission':1.00,'fitid':next_fitid('SH'),
                         'subacctsec':'SHORT','subacctfund':'CASH','selltype':'SELLSHORT'})
            # Cover 2 months later
            d2 = d + timedelta(days=60)
            if d2 <= end_d:
                price2 = _fake_price(ticker, d2)
                txns.append({'type':'BUYSTOCK','date':d2,'ticker':ticker,
                             'units':units,'unitprice':price2,
                             'total':-round(units*price2,2),
                             'commission':1.00,'fitid':next_fitid('BC'),
                             'subacctsec':'SHORT','subacctfund':'CASH','buytype':'BUYTOCOVER'})

    # BUYDEBT / SELLDEBT - Bond trades
    for i, bond in enumerate(bonds):
        buy_d = start + timedelta(days=180 + i * 120)
        if buy_d <= end_d:
            used_secs.add(bond)
            info = SECURITIES[bond]
            units = random.randint(5, 20)
            price = round(info['parvalue'] * random.uniform(0.95, 1.05), 2)
            txns.append({'type':'BUYDEBT','date':buy_d,'ticker':bond,
                         'units':units,'unitprice':price,
                         'total':-round(units*price,2),
                         'commission':0,'fitid':next_fitid('BD'),
                         'subacctsec':'CASH','subacctfund':'CASH'})
            # Sell some bonds later
            if random.random() < 0.5:
                sell_d = buy_d + timedelta(days=random.randint(200, 800))
                if sell_d <= end_d:
                    sp = round(price * random.uniform(0.98, 1.08), 2)
                    txns.append({'type':'SELLDEBT','date':sell_d,'ticker':bond,
                                 'units':units,'unitprice':sp,
                                 'total':round(units*sp,2),
                                 'commission':0,'fitid':next_fitid('SD'),
                                 'subacctsec':'CASH','subacctfund':'CASH'})

    # BUYOPT / SELLOPT - Options trading (from 2021+)
    opt_start = max(start, date(2021, 1, 1))
    for i, opt in enumerate(options):
        buy_d = opt_start + timedelta(days=60 + i * 90)
        if buy_d <= end_d:
            used_secs.add(opt)
            info = SECURITIES[opt]
            contracts = random.randint(1, 10)
            premium = round(random.uniform(2, 50), 2)
            total = -round(contracts * 100 * premium, 2)  # each contract = 100 shares
            txns.append({'type':'BUYOPT','date':buy_d,'ticker':opt,
                         'units':contracts * 100,'unitprice':premium,
                         'total':total,'commission':round(contracts*0.65,2),
                         'fitid':next_fitid('BO'),
                         'subacctsec':'CASH','subacctfund':'CASH',
                         'optbuytype':'BUYTOOPEN'})
            # Close some options
            if random.random() < 0.7:
                close_d = buy_d + timedelta(days=random.randint(14, 90))
                if close_d <= end_d:
                    sell_premium = round(premium * random.uniform(0.3, 3.0), 2)
                    txns.append({'type':'SELLOPT','date':close_d,'ticker':opt,
                                 'units':contracts * 100,'unitprice':sell_premium,
                                 'total':round(contracts*100*sell_premium,2),
                                 'commission':round(contracts*0.65,2),
                                 'fitid':next_fitid('SO'),
                                 'subacctsec':'CASH','subacctfund':'CASH',
                                 'optselltype':'SELLTOCLOSE'})

    # SELLOPT - Write covered calls (SELLTOOPEN)
    if acct['id'] == 'fidelity-brokerage':
        for yr in range(2022, 2026):
            d = date(yr, 6, 15)
            used_secs.add('AAPL_C200_260116')
            txns.append({'type':'SELLOPT','date':d,'ticker':'AAPL_C200_260116',
                         'units':200,'unitprice':round(random.uniform(5,20),2),
                         'total':round(200*random.uniform(5,20),2),
                         'commission':1.30,'fitid':next_fitid('WC'),
                         'subacctsec':'CASH','subacctfund':'CASH',
                         'optselltype':'SELLTOOPEN'})

    # BUYOTHER / SELLOTHER - Futures and Crypto
    for i, fut in enumerate(futures):
        buy_d = max(start, date(2022, 1, 1)) + timedelta(days=30 + i * 60)
        if buy_d <= end_d:
            used_secs.add(fut)
            units = random.randint(1, 5)
            price = _fake_price(fut, buy_d)
            txns.append({'type':'BUYOTHER','date':buy_d,'ticker':fut,
                         'units':units,'unitprice':price,
                         'total':-round(units*price,2),
                         'commission':round(units*2.25,2),
                         'fitid':next_fitid('BF'),
                         'subacctsec':'CASH','subacctfund':'CASH'})
            sell_d = buy_d + timedelta(days=random.randint(5, 60))
            if sell_d <= end_d:
                sp = round(price * random.uniform(0.95, 1.15), 2)
                txns.append({'type':'SELLOTHER','date':sell_d,'ticker':fut,
                             'units':units,'unitprice':sp,
                             'total':round(units*sp,2),
                             'commission':round(units*2.25,2),
                             'fitid':next_fitid('SF'),
                             'subacctsec':'CASH','subacctfund':'CASH'})

    for i, coin in enumerate(crypto):
        buy_d = max(start, date(2021, 6, 1)) + timedelta(days=30 + i * 45)
        if buy_d <= end_d:
            used_secs.add(coin)
            units = round(random.uniform(0.01, 5.0), 6)
            price = _fake_price(coin, buy_d)
            txns.append({'type':'BUYOTHER','date':buy_d,'ticker':coin,
                         'units':units,'unitprice':price,
                         'total':-round(units*price,2),
                         'commission':round(units*price*0.005,2),
                         'fitid':next_fitid('CR'),
                         'subacctsec':'CASH','subacctfund':'CASH'})

    # INCOME - Dividends, interest, capital gains
    for d in _monthly_dates(start, end_d, day=15):
        if random.random() < 0.4:
            ticker = random.choice(stocks + etfs)
            used_secs.add(ticker)
            inctype = random.choice(['DIV','DIV','DIV','INTEREST','CGLONG','CGSHORT','MISC'])
            amt = round(random.uniform(5, 500) * (1 + (d.year-2016)*0.5), 2)
            txns.append({'type':'INCOME','date':d,'ticker':ticker,
                         'incometype':inctype,'total':amt,
                         'fitid':next_fitid('IC'),
                         'subacctsec':'CASH','subacctfund':'CASH'})

    # REINVEST - Dividend reinvestment
    for d in _monthly_dates(start, end_d, day=16):
        if random.random() < 0.2:
            ticker = random.choice(['SPY','VTI','QQQ'])
            used_secs.add(ticker)
            price = _fake_price(ticker, d)
            amt = round(random.uniform(10, 200), 2)
            units = round(amt / price, 6)
            txns.append({'type':'REINVEST','date':d,'ticker':ticker,
                         'incometype':'DIV','units':units,'unitprice':price,
                         'total':amt,'fitid':next_fitid('RI'),
                         'subacctsec':'CASH','subacctfund':'CASH'})

    # TRANSFER - Share transfer (e.g., from another account)
    if acct['id'] == 'fidelity-brokerage':
        d = date(2020, 6, 1)
        ticker = 'FXAIX'
        used_secs.add(ticker)
        txns.append({'type':'TRANSFER','date':d,'ticker':ticker,
                     'units':500.0,'unitprice':120.0,
                     'tferaction':'IN','fitid':next_fitid('TF'),
                     'subacctsec':'CASH'})

    # MARGININTEREST (IBKR)
    if 'ibkr' in acct['id']:
        for d in _monthly_dates(start, end_d, day=28):
            txns.append({'type':'MARGININTEREST','date':d,
                         'total':-round(random.uniform(20, 200),2),
                         'fitid':next_fitid('MI')})

    # RETOFCAP - Return of capital (some ETFs/REITs)
    for yr in range(max(2020, start.year), 2026):
        d = date(yr, 12, 20)
        ticker = random.choice(['SPY','GLD'])
        used_secs.add(ticker)
        txns.append({'type':'RETOFCAP','date':d,'ticker':ticker,
                     'total':round(random.uniform(50, 500),2),
                     'fitid':next_fitid('RC'),
                     'subacctsec':'CASH','subacctfund':'CASH'})

    # SPLIT - Stock split (NVDA 10:1 in 2024, GOOGL 20:1 in 2022)
    if start <= date(2024, 6, 10):
        used_secs.add('NVDA')
        txns.append({'type':'SPLIT','date':date(2024,6,10),'ticker':'NVDA',
                     'units':900,'oldunits':100,'newunits':1000,  # 10:1
                     'numerator':10,'denominator':1,
                     'fitid':next_fitid('SP'),'subacctsec':'CASH'})
    if start <= date(2022, 7, 15):
        used_secs.add('GOOGL')
        txns.append({'type':'SPLIT','date':date(2022,7,15),'ticker':'GOOGL',
                     'units':950,'oldunits':50,'newunits':1000,  # 20:1
                     'numerator':20,'denominator':1,
                     'fitid':next_fitid('SP'),'subacctsec':'CASH'})

    # JRNLSEC - Journal securities between sub-accounts
    if 'ibkr' in acct['id']:
        d = date(2023, 3, 1)
        used_secs.add('AAPL')
        txns.append({'type':'JRNLSEC','date':d,'ticker':'AAPL',
                     'units':50,'subacctfrom':'CASH','subacctto':'MARGIN',
                     'fitid':next_fitid('JS')})

    # JRNLFUND - Journal cash between sub-accounts
    if 'ibkr' in acct['id']:
        d = date(2023, 4, 1)
        txns.append({'type':'JRNLFUND','date':d,
                     'total':10000.00,'subacctfrom':'CASH','subacctto':'MARGIN',
                     'fitid':next_fitid('JF')})

    # Cash withdrawal (INVBANKTRAN)
    for yr in range(start.year, 2026):
        if random.random() < 0.3:
            d = date(yr, random.randint(1,12), 20)
            if d >= start and d <= end_d:
                txns.append({'type':'INVBANKTRAN','date':d,
                             'amount':-round(random.uniform(1000,10000),2),
                             'trntype':'XFER','name':'ACH WITHDRAWAL',
                             'fitid':next_fitid('IW'),'subacctfund':'CASH'})

    txns.sort(key=lambda t: t['date'])
    return txns, used_secs


def gen_inv_txns_retirement(acct, fmt):
    """Generate 401k/IRA transactions."""
    txns = []
    start = acct['start']
    end_d = acct.get('end') or END
    if end_d > END:
        end_d = END
    used_secs = set()

    # Map accounts to their fund sets
    fund_map = {
        'fidelity-401k': ['FXAIX','FCNTX','VBTLX'],
        'vanguard-401k': ['VFIAX','VTIVX','VBTLX','VXUS'],
        'schwab-401k': ['SWPPX','DODGX','BND'],
        'fidelity-rollover': ['FXAIX','FCNTX','VBTLX','SPY','QQQ','VTI'],
    }
    funds = fund_map.get(acct['id'], ['VFIAX','VBTLX'])

    # Bi-weekly contributions (401k) or monthly (IRA)
    if '401k' in acct['id']:
        contribution_base = {2016:300,2017:350,2018:450,2019:550,2020:700,
                             2021:800,2022:950,2023:1100,2024:1400,2025:1500}
        for d in _biweekly_dates(start, end_d):
            contrib = contribution_base.get(d.year, 500)
            match_pct = 0.5  # 50% match
            employee = round(contrib + random.uniform(-20, 20), 2)
            employer = round(employee * match_pct, 2)

            # INVBANKTRAN for employee contribution
            txns.append({'type':'INVBANKTRAN','date':d,'amount':employee,
                         'trntype':'DEP','name':'EMPLOYEE 401K CONTRIBUTION',
                         'fitid':next_fitid('EC'),'subacctfund':'OTHER'})
            # INVBANKTRAN for employer match
            txns.append({'type':'INVBANKTRAN','date':d,'amount':employer,
                         'trntype':'DEP','name':'EMPLOYER MATCH',
                         'fitid':next_fitid('EM'),'subacctfund':'OTHER'})

            # BUYMF - Buy mutual funds with contributions
            total_contrib = employee + employer
            for fund in funds:
                used_secs.add(fund)
                alloc = total_contrib / len(funds)
                price = _fake_price(fund, d)
                units = round(alloc / price, 6)
                txns.append({'type':'BUYMF','date':d,'ticker':fund,
                             'units':units,'unitprice':price,
                             'total':-round(alloc,2),
                             'commission':0,'fitid':next_fitid('BM'),
                             'subacctsec':'OTHER','subacctfund':'OTHER',
                             'buytype':'BUY'})
    else:
        # IRA - Monthly contributions + initial rollover
        if 'rollover' in acct['id']:
            # Rollover transfer in
            for fund in ['FXAIX','FCNTX']:
                used_secs.add(fund)
                price = _fake_price(fund, start)
                units = round(random.uniform(200, 800), 6)
                txns.append({'type':'TRANSFER','date':start,'ticker':fund,
                             'units':units,'unitprice':price,
                             'tferaction':'IN','fitid':next_fitid('RO'),
                             'subacctsec':'OTHER'})

        for d in _monthly_dates(start, end_d, day=5):
            contrib = round(random.uniform(500, 2000) * (1 + (d.year-2016)*0.2), 2)
            txns.append({'type':'INVBANKTRAN','date':d,'amount':contrib,
                         'trntype':'DEP','name':'IRA CONTRIBUTION',
                         'fitid':next_fitid('IC'),'subacctfund':'OTHER'})
            for fund in funds:
                used_secs.add(fund)
                alloc = contrib / len(funds)
                price = _fake_price(fund, d)
                units = round(alloc / price, 6)
                txns.append({'type':'BUYMF','date':d,'ticker':fund,
                             'units':units,'unitprice':price,
                             'total':-round(alloc,2),
                             'commission':0,'fitid':next_fitid('BM'),
                             'subacctsec':'OTHER','subacctfund':'OTHER',
                             'buytype':'BUY'})

    # SELLMF - Rebalancing (sell one fund, buy another) annually
    for yr in range(start.year + 1, min(end_d.year + 1, 2026)):
        d = date(yr, 4, 1)
        if d > end_d:
            break
        sell_fund = funds[0]
        buy_fund = funds[-1]
        used_secs.add(sell_fund)
        used_secs.add(buy_fund)
        price = _fake_price(sell_fund, d)
        units = round(random.uniform(10, 50), 6)
        txns.append({'type':'SELLMF','date':d,'ticker':sell_fund,
                     'units':units,'unitprice':price,
                     'total':round(units*price,2),
                     'commission':0,'fitid':next_fitid('SM'),
                     'subacctsec':'OTHER','subacctfund':'OTHER','selltype':'SELL'})
        buy_price = _fake_price(buy_fund, d)
        buy_units = round((units * price) / buy_price, 6)
        txns.append({'type':'BUYMF','date':d,'ticker':buy_fund,
                     'units':buy_units,'unitprice':buy_price,
                     'total':-round(buy_units*buy_price,2),
                     'commission':0,'fitid':next_fitid('BM'),
                     'subacctsec':'OTHER','subacctfund':'OTHER','buytype':'BUY'})

    # REINVEST - Dividend reinvestment quarterly
    for d in _monthly_dates(start, end_d, day=15):
        if d.month in (3, 6, 9, 12):
            fund = random.choice(funds)
            used_secs.add(fund)
            price = _fake_price(fund, d)
            amt = round(random.uniform(20, 500) * (1 + (d.year-2016)*0.5), 2)
            units = round(amt / price, 6)
            txns.append({'type':'REINVEST','date':d,'ticker':fund,
                         'incometype':'DIV','units':units,'unitprice':price,
                         'total':amt,'fitid':next_fitid('RI'),
                         'subacctsec':'OTHER','subacctfund':'OTHER'})

    # INCOME - Interest and capital gains distributions
    for yr in range(start.year, min(end_d.year + 1, 2026)):
        d = date(yr, 12, 15)
        if d < start or d > end_d:
            continue
        for fund in funds:
            used_secs.add(fund)
            for inctype in ['DIV','CGLONG']:
                amt = round(random.uniform(50, 1000) * (1 + (yr-2016)*0.4), 2)
                txns.append({'type':'INCOME','date':d,'ticker':fund,
                             'incometype':inctype,'total':amt,
                             'fitid':next_fitid('DI'),
                             'subacctsec':'OTHER','subacctfund':'OTHER'})

    txns.sort(key=lambda t: t['date'])
    return txns, used_secs


def _fake_price(ticker, d):
    """Generate a fake but somewhat realistic price for a security on a date."""
    base_prices = {
        'AAPL':95,'MSFT':55,'NVDA':30,'AMZN':650,'GOOGL':750,'TSLA':200,
        'JPM':60,'V':75,'JNJ':100,'BRKB':140,
        'SPY':200,'QQQ':110,'VTI':105,'VXUS':45,'BND':80,'GLD':120,'ARKK':45,
        'VFIAX':200,'FXAIX':100,'VBTLX':10.5,'SWPPX':45,'DODGX':170,
        'VTIVX':18,'FCNTX':110,
        'UST10Y':980,'UST2Y':995,'AAPLBD':1010,'MSFTBD':1005,'CAMUBD':5050,
        'AAPL_C200_260116':8.50,'NVDA_C500_260320':15.00,
        'SPY_P400_250620':6.00,'TSLA_P250_251219':12.00,'AMZN_C200_250919':10.00,
        'ES':4200,'NQ':14500,'GC':1800,'CL':75,
        'BTC':35000,'ETH':2000,'SOL':100,
    }
    base = base_prices.get(ticker, 100)
    # Simulate growth over time (2016 -> 2025)
    years_elapsed = (d - date(2016, 1, 1)).days / 365.25
    growth_rates = {
        'AAPL':0.25,'MSFT':0.28,'NVDA':0.65,'AMZN':0.20,'GOOGL':0.18,
        'TSLA':0.35,'JPM':0.12,'V':0.18,'JNJ':0.06,'BRKB':0.10,
        'SPY':0.12,'QQQ':0.18,'VTI':0.11,'VXUS':0.05,'BND':0.02,'GLD':0.08,'ARKK':-0.05,
        'VFIAX':0.12,'FXAIX':0.12,'VBTLX':0.02,'SWPPX':0.12,'DODGX':0.10,
        'VTIVX':0.09,'FCNTX':0.14,
        'BTC':0.80,'ETH':0.70,'SOL':0.90,
    }
    rate = growth_rates.get(ticker, 0.08)
    price = base * (1 + rate) ** years_elapsed
    # Add some random noise
    price *= random.uniform(0.92, 1.08)
    return round(price, 2)


# ============================================================================
# INVESTMENT POSITIONS GENERATOR
# ============================================================================

def gen_positions(acct_id, used_secs, fmt):
    """Generate INVPOSLIST for an account."""
    lines = ['<INVPOSLIST>']
    # Determine final holdings based on account type
    target_values = {
        'fidelity-brokerage': 2800000,
        'schwab-taxable': 1500000,
        'ibkr-margin': 800000,
        'fidelity-401k': 0,
        'vanguard-401k': 1200000,
        'schwab-401k': 600000,
        'fidelity-rollover': 2700000,
    }
    target = target_values.get(acct_id, 500000)
    if target == 0:
        lines.append('</INVPOSLIST>')
        return '\n'.join(lines)

    secs_list = list(used_secs)
    if not secs_list:
        lines.append('</INVPOSLIST>')
        return '\n'.join(lines)

    per_sec = target / len(secs_list)

    for ticker in secs_list:
        info = SECURITIES[ticker]
        price = _fake_price(ticker, END)
        units = round(per_sec / price, 4) if price > 0 else 0
        mktval = round(units * price, 2)

        pos_type_map = {
            'stock': ('POSSTOCK', 'POSSTOCK'),
            'mf': ('POSMF', 'POSMF'),
            'debt': ('POSDEBT', 'POSDEBT'),
            'opt': ('POSOPT', 'POSOPT'),
            'other': ('POSOTHER', 'POSOTHER'),
        }
        outer_tag = pos_type_map.get(info['stype'], ('POSOTHER','POSOTHER'))[0]

        lines.append(f'<{outer_tag}>')
        lines.append('<INVPOS>')
        lines.append(secid_block(info['cusip'], fmt))
        lines.append(E('UNITS', f'{units:.4f}', fmt))
        lines.append(E('UNITPRICE', money(price), fmt))
        lines.append(E('MKTVAL', money(mktval), fmt))
        lines.append(E('DTPRICEASOF', dtfmt(END), fmt))
        lines.append(E('MEMO', ticker, fmt))
        lines.append('</INVPOS>')
        lines.append(f'</{outer_tag}>')

    lines.append('</INVPOSLIST>')
    return '\n'.join(lines)


# ============================================================================
# FORMAT INVESTMENT TRANSACTIONS AS OFX
# ============================================================================

def format_inv_txn(t, fmt):
    """Format a single investment transaction."""
    lines = []
    ttype = t['type']

    if ttype == 'INVBANKTRAN':
        lines.append('<INVBANKTRAN>')
        lines.append('<STMTTRN>')
        lines.append(E('TRNTYPE', t.get('trntype','OTHER'), fmt))
        lines.append(E('DTPOSTED', dtfmt(t['date']), fmt))
        lines.append(E('TRNAMT', money(t['amount']), fmt))
        lines.append(E('FITID', t['fitid'], fmt))
        lines.append(E('NAME', t.get('name',''), fmt))
        lines.append('</STMTTRN>')
        lines.append(E('SUBACCTFUND', t.get('subacctfund','CASH'), fmt))
        lines.append('</INVBANKTRAN>')

    elif ttype in ('BUYSTOCK','SELLSTOCK'):
        outer = ttype
        inner = 'INVBUY' if 'BUY' in ttype else 'INVSELL'
        lines.append(f'<{outer}>')
        lines.append(f'<{inner}>')
        lines.append('<INVTRAN>')
        lines.append(E('FITID', t['fitid'], fmt))
        lines.append(E('DTTRADE', dtfmt(t['date']), fmt))
        settle = t['date'] + timedelta(days=2)
        lines.append(E('DTSETTLE', dtfmt(settle), fmt))
        lines.append('</INVTRAN>')
        lines.append(secid_block(SECURITIES[t['ticker']]['cusip'], fmt))
        lines.append(E('UNITS', f"{t['units']:.4f}", fmt))
        lines.append(E('UNITPRICE', money(t['unitprice']), fmt))
        if t.get('commission'):
            lines.append(E('COMMISSION', money(t['commission']), fmt))
        lines.append(E('TOTAL', money(t['total']), fmt))
        lines.append(E('SUBACCTSEC', t.get('subacctsec','CASH'), fmt))
        lines.append(E('SUBACCTFUND', t.get('subacctfund','CASH'), fmt))
        lines.append(f'</{inner}>')
        if 'BUY' in ttype:
            lines.append(E('BUYTYPE', t.get('buytype','BUY'), fmt))
        else:
            lines.append(E('SELLTYPE', t.get('selltype','SELL'), fmt))
        lines.append(f'</{outer}>')

    elif ttype in ('BUYMF','SELLMF'):
        outer = ttype
        inner = 'INVBUY' if 'BUY' in ttype else 'INVSELL'
        lines.append(f'<{outer}>')
        lines.append(f'<{inner}>')
        lines.append('<INVTRAN>')
        lines.append(E('FITID', t['fitid'], fmt))
        lines.append(E('DTTRADE', dtfmt(t['date']), fmt))
        lines.append('</INVTRAN>')
        lines.append(secid_block(SECURITIES[t['ticker']]['cusip'], fmt))
        lines.append(E('UNITS', f"{t['units']:.6f}", fmt))
        lines.append(E('UNITPRICE', money(t['unitprice']), fmt))
        lines.append(E('TOTAL', money(t['total']), fmt))
        lines.append(E('SUBACCTSEC', t.get('subacctsec','OTHER'), fmt))
        lines.append(E('SUBACCTFUND', t.get('subacctfund','OTHER'), fmt))
        lines.append(f'</{inner}>')
        if 'BUY' in ttype:
            lines.append(E('BUYTYPE', t.get('buytype','BUY'), fmt))
        else:
            lines.append(E('SELLTYPE', t.get('selltype','SELL'), fmt))
        lines.append(f'</{outer}>')

    elif ttype in ('BUYDEBT','SELLDEBT'):
        outer = ttype
        inner = 'INVBUY' if 'BUY' in ttype else 'INVSELL'
        lines.append(f'<{outer}>')
        lines.append(f'<{inner}>')
        lines.append('<INVTRAN>')
        lines.append(E('FITID', t['fitid'], fmt))
        lines.append(E('DTTRADE', dtfmt(t['date']), fmt))
        lines.append('</INVTRAN>')
        lines.append(secid_block(SECURITIES[t['ticker']]['cusip'], fmt))
        lines.append(E('UNITS', f"{t['units']:.4f}", fmt))
        lines.append(E('UNITPRICE', money(t['unitprice']), fmt))
        lines.append(E('TOTAL', money(t['total']), fmt))
        lines.append(E('SUBACCTSEC', t.get('subacctsec','CASH'), fmt))
        lines.append(E('SUBACCTFUND', t.get('subacctfund','CASH'), fmt))
        lines.append(f'</{inner}>')
        lines.append(f'</{outer}>')

    elif ttype in ('BUYOPT','SELLOPT'):
        outer = ttype
        inner = 'INVBUY' if 'BUY' in ttype else 'INVSELL'
        lines.append(f'<{outer}>')
        lines.append(f'<{inner}>')
        lines.append('<INVTRAN>')
        lines.append(E('FITID', t['fitid'], fmt))
        lines.append(E('DTTRADE', dtfmt(t['date']), fmt))
        lines.append('</INVTRAN>')
        lines.append(secid_block(SECURITIES[t['ticker']]['cusip'], fmt))
        lines.append(E('UNITS', f"{t['units']:.4f}", fmt))
        lines.append(E('UNITPRICE', money(t['unitprice']), fmt))
        if t.get('commission'):
            lines.append(E('COMMISSION', money(t['commission']), fmt))
        lines.append(E('TOTAL', money(t['total']), fmt))
        lines.append(E('SUBACCTSEC', t.get('subacctsec','CASH'), fmt))
        lines.append(E('SUBACCTFUND', t.get('subacctfund','CASH'), fmt))
        lines.append(f'</{inner}>')
        if 'BUY' in ttype:
            lines.append(E('OPTBUYTYPE', t.get('optbuytype','BUYTOOPEN'), fmt))
        else:
            lines.append(E('OPTSELLTYPE', t.get('optselltype','SELLTOCLOSE'), fmt))
        lines.append(f'</{outer}>')

    elif ttype in ('BUYOTHER','SELLOTHER'):
        outer = ttype
        inner = 'INVBUY' if 'BUY' in ttype else 'INVSELL'
        lines.append(f'<{outer}>')
        lines.append(f'<{inner}>')
        lines.append('<INVTRAN>')
        lines.append(E('FITID', t['fitid'], fmt))
        lines.append(E('DTTRADE', dtfmt(t['date']), fmt))
        lines.append('</INVTRAN>')
        lines.append(secid_block(SECURITIES[t['ticker']]['cusip'], fmt))
        lines.append(E('UNITS', f"{t['units']:.6f}", fmt))
        lines.append(E('UNITPRICE', money(t['unitprice']), fmt))
        if t.get('commission'):
            lines.append(E('COMMISSION', money(t['commission']), fmt))
        lines.append(E('TOTAL', money(t['total']), fmt))
        lines.append(E('SUBACCTSEC', t.get('subacctsec','CASH'), fmt))
        lines.append(E('SUBACCTFUND', t.get('subacctfund','CASH'), fmt))
        lines.append(f'</{inner}>')
        lines.append(f'</{outer}>')

    elif ttype == 'INCOME':
        lines.append('<INCOME>')
        lines.append('<INVTRAN>')
        lines.append(E('FITID', t['fitid'], fmt))
        lines.append(E('DTTRADE', dtfmt(t['date']), fmt))
        lines.append('</INVTRAN>')
        lines.append(secid_block(SECURITIES[t['ticker']]['cusip'], fmt))
        lines.append(E('INCOMETYPE', t['incometype'], fmt))
        lines.append(E('TOTAL', money(t['total']), fmt))
        lines.append(E('SUBACCTSEC', t.get('subacctsec','CASH'), fmt))
        lines.append(E('SUBACCTFUND', t.get('subacctfund','CASH'), fmt))
        lines.append('</INCOME>')

    elif ttype == 'REINVEST':
        lines.append('<REINVEST>')
        lines.append('<INVTRAN>')
        lines.append(E('FITID', t['fitid'], fmt))
        lines.append(E('DTTRADE', dtfmt(t['date']), fmt))
        lines.append('</INVTRAN>')
        lines.append(secid_block(SECURITIES[t['ticker']]['cusip'], fmt))
        lines.append(E('INCOMETYPE', t.get('incometype','DIV'), fmt))
        lines.append(E('TOTAL', money(t['total']), fmt))
        lines.append(E('UNITS', f"{t['units']:.6f}", fmt))
        lines.append(E('UNITPRICE', money(t['unitprice']), fmt))
        lines.append(E('SUBACCTSEC', t.get('subacctsec','CASH'), fmt))
        lines.append(E('SUBACCTFUND', t.get('subacctfund','CASH'), fmt))
        lines.append('</REINVEST>')

    elif ttype == 'TRANSFER':
        lines.append('<TRANSFER>')
        lines.append('<INVTRAN>')
        lines.append(E('FITID', t['fitid'], fmt))
        lines.append(E('DTTRADE', dtfmt(t['date']), fmt))
        lines.append('</INVTRAN>')
        lines.append(secid_block(SECURITIES[t['ticker']]['cusip'], fmt))
        lines.append(E('UNITS', f"{t['units']:.4f}", fmt))
        lines.append(E('TFERACTION', t.get('tferaction','IN'), fmt))
        lines.append(E('SUBACCTSEC', t.get('subacctsec','CASH'), fmt))
        lines.append('</TRANSFER>')

    elif ttype == 'MARGININTEREST':
        lines.append('<MARGININTEREST>')
        lines.append('<INVTRAN>')
        lines.append(E('FITID', t['fitid'], fmt))
        lines.append(E('DTTRADE', dtfmt(t['date']), fmt))
        lines.append('</INVTRAN>')
        lines.append(E('TOTAL', money(t['total']), fmt))
        lines.append('</MARGININTEREST>')

    elif ttype == 'RETOFCAP':
        lines.append('<RETOFCAP>')
        lines.append('<INVTRAN>')
        lines.append(E('FITID', t['fitid'], fmt))
        lines.append(E('DTTRADE', dtfmt(t['date']), fmt))
        lines.append('</INVTRAN>')
        lines.append(secid_block(SECURITIES[t['ticker']]['cusip'], fmt))
        lines.append(E('TOTAL', money(t['total']), fmt))
        lines.append(E('SUBACCTSEC', t.get('subacctsec','CASH'), fmt))
        lines.append(E('SUBACCTFUND', t.get('subacctfund','CASH'), fmt))
        lines.append('</RETOFCAP>')

    elif ttype == 'SPLIT':
        lines.append('<SPLIT>')
        lines.append('<INVTRAN>')
        lines.append(E('FITID', t['fitid'], fmt))
        lines.append(E('DTTRADE', dtfmt(t['date']), fmt))
        lines.append('</INVTRAN>')
        lines.append(secid_block(SECURITIES[t['ticker']]['cusip'], fmt))
        lines.append(E('SUBACCTSEC', t.get('subacctsec','CASH'), fmt))
        lines.append(E('OLDUNITS', f"{t['oldunits']:.4f}", fmt))
        lines.append(E('NEWUNITS', f"{t['newunits']:.4f}", fmt))
        lines.append(E('NUMERATOR', str(t['numerator']), fmt))
        lines.append(E('DENOMINATOR', str(t['denominator']), fmt))
        lines.append('</SPLIT>')

    elif ttype == 'JRNLSEC':
        lines.append('<JRNLSEC>')
        lines.append('<INVTRAN>')
        lines.append(E('FITID', t['fitid'], fmt))
        lines.append(E('DTTRADE', dtfmt(t['date']), fmt))
        lines.append('</INVTRAN>')
        lines.append(secid_block(SECURITIES[t['ticker']]['cusip'], fmt))
        lines.append(E('UNITS', f"{t['units']:.4f}", fmt))
        lines.append(E('SUBACCTFROM', t['subacctfrom'], fmt))
        lines.append(E('SUBACCTTO', t['subacctto'], fmt))
        lines.append('</JRNLSEC>')

    elif ttype == 'JRNLFUND':
        lines.append('<JRNLFUND>')
        lines.append('<INVTRAN>')
        lines.append(E('FITID', t['fitid'], fmt))
        lines.append(E('DTTRADE', dtfmt(t['date']), fmt))
        lines.append('</INVTRAN>')
        lines.append(E('TOTAL', money(t['total']), fmt))
        lines.append(E('SUBACCTFROM', t['subacctfrom'], fmt))
        lines.append(E('SUBACCTTO', t['subacctto'], fmt))
        lines.append('</JRNLFUND>')

    return '\n'.join(lines)


def format_inv_stmt(acct, txns, used_secs, fmt):
    """Format a complete INVSTMTMSGSRSV1 block."""
    txn_lines = '\n'.join(format_inv_txn(t, fmt) for t in txns)
    pos_lines = gen_positions(acct['id'], used_secs, fmt)

    # Calculate approximate cash balance
    cash_deposits = sum(t.get('amount', 0) for t in txns if t['type'] == 'INVBANKTRAN')
    cash_from_sells = sum(t.get('total', 0) for t in txns if t['type'] in ('SELLSTOCK','SELLMF','SELLDEBT','SELLOPT','SELLOTHER') and t.get('total',0) > 0)
    cash_from_income = sum(t.get('total', 0) for t in txns if t['type'] in ('INCOME','RETOFCAP') and t.get('total',0) > 0)
    cash_from_margin = sum(t.get('total', 0) for t in txns if t['type'] == 'MARGININTEREST')
    avail_cash = round(cash_deposits + cash_from_sells + cash_from_income + cash_from_margin, 2)
    avail_cash = max(1000, avail_cash * 0.1)  # Keep ~10% as cash

    start_d = acct['start']
    end_d = acct.get('end') or END
    if end_d > END:
        end_d = END

    return '\n'.join([
        '<INVSTMTMSGSRSV1>','<INVSTMTTRNRS>',
        E('TRNUID', next_fitid('ITUID'), fmt), status_ok(fmt),
        '<INVSTMTRS>',
        E('DTASOF', dtfmt(end_d), fmt),
        E('CURDEF', 'USD', fmt),
        '<INVACCTFROM>',
        E('BROKERID', acct['brokerid'], fmt),
        E('ACCTID', acct['acctid'], fmt),
        '</INVACCTFROM>',
        '<INVTRANLIST>',
        E('DTSTART', dtfmt(start_d), fmt),
        E('DTEND', dtfmt(end_d), fmt),
        txn_lines,
        '</INVTRANLIST>',
        pos_lines,
        '<INVBAL>',
        E('AVAILCASH', money(avail_cash), fmt),
        E('MARGVAL', money(0) if 'ibkr' not in acct['id'] else money(round(avail_cash * 2, 2)), fmt),
        E('SHORTVAL', money(0) if 'ibkr' not in acct['id'] else money(-round(random.uniform(5000, 50000), 2)), fmt),
        '</INVBAL>',
        '</INVSTMTRS>','</INVSTMTTRNRS>','</INVSTMTMSGSRSV1>',
    ])


# ============================================================================
# SECURITY LIST GENERATOR
# ============================================================================

def gen_seclist(used_secs, fmt):
    """Generate SECLISTMSGSRSV1 with all security types."""
    lines = ['<SECLISTMSGSRSV1>','<SECLIST>']

    for ticker in sorted(used_secs):
        info = SECURITIES.get(ticker)
        if not info:
            continue

        if info['stype'] == 'stock':
            lines.append('<STOCKINFO>')
            lines.append('<SECINFO>')
            lines.append(secid_block(info['cusip'], fmt))
            lines.append(E('SECNAME', info['name'], fmt))
            lines.append(E('TICKER', ticker, fmt))
            lines.append(E('FIID', info['cusip'], fmt))
            lines.append('</SECINFO>')
            lines.append(E('STOCKTYPE', info.get('stocktype','COMMON'), fmt))
            lines.append('</STOCKINFO>')

        elif info['stype'] == 'mf':
            lines.append('<MFINFO>')
            lines.append('<SECINFO>')
            lines.append(secid_block(info['cusip'], fmt))
            lines.append(E('SECNAME', info['name'], fmt))
            lines.append(E('TICKER', ticker, fmt))
            lines.append('</SECINFO>')
            lines.append(E('MFTYPE', info.get('mftype','OPENEND'), fmt))
            lines.append('</MFINFO>')

        elif info['stype'] == 'debt':
            lines.append('<DEBTINFO>')
            lines.append('<SECINFO>')
            lines.append(secid_block(info['cusip'], fmt))
            lines.append(E('SECNAME', info['name'], fmt))
            lines.append(E('TICKER', ticker, fmt))
            lines.append('</SECINFO>')
            lines.append(E('PARVALUE', money(info.get('parvalue',1000)), fmt))
            lines.append(E('DEBTTYPE', info.get('debttype','COUPON'), fmt))
            lines.append(E('DTMAT', info.get('dtmat','20301231') + '120000', fmt))
            lines.append(E('COUPONRT', str(info.get('couponrt',0)), fmt))
            lines.append(E('COUPONFREQ', info.get('couponfreq','SEMIANNUAL'), fmt))
            lines.append('</DEBTINFO>')

        elif info['stype'] == 'opt':
            lines.append('<OPTINFO>')
            lines.append('<SECINFO>')
            lines.append(secid_block(info['cusip'], fmt))
            lines.append(E('SECNAME', info['name'], fmt))
            lines.append(E('TICKER', ticker, fmt))
            lines.append('</SECINFO>')
            lines.append(E('OPTTYPE', info['opttype'], fmt))
            lines.append(E('STRIKEPRICE', money(info['strikeprice']), fmt))
            lines.append(E('DTEXPIRE', info['dtexpire'] + '120000', fmt))
            lines.append(E('SHPERCTRCT', str(info['shperctrct']), fmt))
            lines.append('<SECID>')
            lines.append(E('UNIQUEID', info['underlying'], fmt))
            lines.append(E('UNIQUEIDTYPE', 'CUSIP', fmt))
            lines.append('</SECID>')
            lines.append('</OPTINFO>')

        elif info['stype'] == 'other':
            lines.append('<OTHERINFO>')
            lines.append('<SECINFO>')
            lines.append(secid_block(info['cusip'], fmt))
            lines.append(E('SECNAME', info['name'], fmt))
            lines.append(E('TICKER', ticker, fmt))
            lines.append('</SECINFO>')
            lines.append(E('TYPEDESC', info.get('typedesc','Other'), fmt))
            lines.append('</OTHERINFO>')

    lines.append('</SECLIST>')
    lines.append('</SECLISTMSGSRSV1>')
    return '\n'.join(lines)


# ============================================================================
# FULL OFX DOCUMENT ASSEMBLY
# ============================================================================

def build_bank_ofx(accts, fmt):
    """Build OFX for one or more bank accounts."""
    org = accts[0]['org']
    fid = accts[0]['fid']
    parts = [ofx_header(fmt), '<OFX>', signon(org, fid, fmt)]
    for acct in accts:
        stmt, _ = gen_bank_txns(acct, fmt)
        parts.append(stmt)
    parts.append('</OFX>')
    return '\n'.join(parts)

def build_cc_ofx(accts, fmt):
    """Build OFX for one or more credit card accounts."""
    org = accts[0]['org']
    fid = accts[0]['fid']
    parts = [ofx_header(fmt), '<OFX>', signon(org, fid, fmt)]
    for acct in accts:
        txns, bal = gen_cc_txns(acct, fmt)
        parts.append(format_cc_stmt(acct, txns, bal, fmt))
    parts.append('</OFX>')
    return '\n'.join(parts)

def build_inv_ofx(accts, is_retirement, fmt):
    """Build OFX for one or more investment accounts."""
    org = accts[0]['org']
    fid = accts[0]['fid']
    all_secs = set()
    stmt_parts = []
    for acct in accts:
        if is_retirement:
            txns, used = gen_inv_txns_retirement(acct, fmt)
        else:
            txns, used = gen_inv_txns_brokerage(acct, fmt)
        all_secs.update(used)
        stmt_parts.append(format_inv_stmt(acct, txns, used, fmt))

    parts = [ofx_header(fmt), '<OFX>', signon(org, fid, fmt)]
    parts.extend(stmt_parts)
    parts.append(gen_seclist(all_secs, fmt))
    parts.append('</OFX>')
    return '\n'.join(parts)


def build_mega_ofx(fmt='sgml'):
    """Build one mega OFX file with ALL accounts."""
    all_secs = set()
    parts = [ofx_header(fmt), '<OFX>', signon('YMoney Aggregator', '99999', fmt)]

    # Bank accounts
    for acct in BANK_ACCTS:
        stmt, _ = gen_bank_txns(acct, fmt)
        parts.append(stmt)

    # Credit cards
    for acct in CC_ACCTS:
        txns, bal = gen_cc_txns(acct, fmt)
        parts.append(format_cc_stmt(acct, txns, bal, fmt))

    # Brokerage
    for acct in BROKERAGE_ACCTS:
        txns, used = gen_inv_txns_brokerage(acct, fmt)
        all_secs.update(used)
        parts.append(format_inv_stmt(acct, txns, used, fmt))

    # Retirement
    for acct in RETIREMENT_ACCTS:
        txns, used = gen_inv_txns_retirement(acct, fmt)
        all_secs.update(used)
        parts.append(format_inv_stmt(acct, txns, used, fmt))

    parts.append(gen_seclist(all_secs, fmt))
    parts.append('</OFX>')
    return '\n'.join(parts)


# ============================================================================
# FILE OUTPUT
# ============================================================================

def write_file(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"  wrote {path} ({len(content):,} bytes)")

def generate_all():
    print("=" * 60)
    print("OFX Test Data Generator for YMoney")
    print("=" * 60)

    # --- 1. mega/ (one giant OFX, SGML format) ---
    print("\n[1/3] Generating mega/ (single OFX, SGML v1 format)...")
    mega = build_mega_ofx('sgml')
    write_file(os.path.join(BASE_DIR, 'mega', 'all-accounts.ofx'), mega)

    # --- 2. by-type/ (one OFX per account type, XML format) ---
    print("\n[2/3] Generating by-type/ (per-type OFX, XML v2 format)...")
    # Reset sequence for reproducibility per-section
    write_file(os.path.join(BASE_DIR, 'by-type', 'bank-accounts.ofx'),
               build_bank_ofx(BANK_ACCTS, 'xml'))
    write_file(os.path.join(BASE_DIR, 'by-type', 'credit-cards.ofx'),
               build_cc_ofx(CC_ACCTS, 'xml'))
    write_file(os.path.join(BASE_DIR, 'by-type', 'brokerage.ofx'),
               build_inv_ofx(BROKERAGE_ACCTS, False, 'xml'))
    write_file(os.path.join(BASE_DIR, 'by-type', 'retirement-401k.ofx'),
               build_inv_ofx(RETIREMENT_ACCTS, True, 'xml'))

    # --- 3. by-account/ (one OFX per account, mixed formats) ---
    print("\n[3/3] Generating by-account/ (per-account OFX, mixed formats)...")

    # Bank accounts: alternate SGML/XML
    for i, acct in enumerate(BANK_ACCTS):
        fmt = 'sgml' if i % 2 == 0 else 'xml'
        write_file(os.path.join(BASE_DIR, 'by-account', f"{acct['id']}.ofx"),
                   build_bank_ofx([acct], fmt))

    # Credit cards: alternate
    for i, acct in enumerate(CC_ACCTS):
        fmt = 'xml' if i % 2 == 0 else 'sgml'
        write_file(os.path.join(BASE_DIR, 'by-account', f"{acct['id']}.ofx"),
                   build_cc_ofx([acct], fmt))

    # Brokerage: alternate
    for i, acct in enumerate(BROKERAGE_ACCTS):
        fmt = 'sgml' if i % 2 == 0 else 'xml'
        write_file(os.path.join(BASE_DIR, 'by-account', f"{acct['id']}.ofx"),
                   build_inv_ofx([acct], False, fmt))

    # Retirement: alternate
    for i, acct in enumerate(RETIREMENT_ACCTS):
        fmt = 'xml' if i % 2 == 0 else 'sgml'
        write_file(os.path.join(BASE_DIR, 'by-account', f"{acct['id']}.ofx"),
                   build_inv_ofx([acct], True, fmt))

    print("\n" + "=" * 60)
    print("Done! Generated test data in:", BASE_DIR)

    # Summary
    for dirpath, dirnames, filenames in os.walk(BASE_DIR):
        for f in sorted(filenames):
            fp = os.path.join(dirpath, f)
            sz = os.path.getsize(fp)
            rel = os.path.relpath(fp, BASE_DIR)
            print(f"  {rel:45s} {sz:>10,} bytes")


if __name__ == '__main__':
    generate_all()
