package com.rootdowndigital.ouispy.wifiadapter

internal object AdsbEnrich {
    fun airline(callsign: String?): String? = airlineRow(callsign)?.first

    fun operatorCountry(callsign: String?): String? = airlineRow(callsign)?.second

    fun country(icaoHex: String): String? {
        val a = icaoHex.trim().toIntOrNull(16) ?: return null
        var best = -1
        var bestSpan = Int.MAX_VALUE
        for (i in RANGE_START.indices) {
            if (a >= RANGE_START[i] && a <= RANGE_END[i] && RANGE_END[i] - RANGE_START[i] < bestSpan) {
                best = i
                bestSpan = RANGE_END[i] - RANGE_START[i]
            }
        }
        return if (best < 0) null else RANGE_NAME[best]
    }

    fun demo() {
        check(country("A12345") == "United States")
        check(country("400123") == "United Kingdom")
        check(country("789ABC") == "Hong Kong")
        check(country("780001") == "China")
        check(country("3C4A12") == "Germany")
        check(country("zzzzzz") == null)
        check(airline("UAL123") == "United Airlines")
        check(operatorCountry("DLH45A") == "Germany")
        check(airline("N123AB") == null)
        check(airline("GABCD") == null)
        check(airline(null) == null)
    }

    private fun airlineRow(callsign: String?): Pair<String, String?>? {
        val c = callsign?.trim()?.uppercase() ?: return null
        if (c.length < 4) return null
        if (c[0] == 'N' && c[1].isDigit()) return null
        if (!(c[0] in 'A'..'Z' && c[1] in 'A'..'Z' && c[2] in 'A'..'Z' && c[3].isDigit())) return null
        return AIRLINE_MAP[c.substring(0, 3)]
    }

    private val RANGE_ROWS: List<List<String>> by lazy {
        ICAO_RANGES.lineSequence().filter { it.isNotBlank() }.map { it.split(',', limit = 3) }.toList()
    }
    private val RANGE_START: IntArray by lazy { IntArray(RANGE_ROWS.size) { RANGE_ROWS[it][0].toInt(16) } }
    private val RANGE_END: IntArray by lazy { IntArray(RANGE_ROWS.size) { RANGE_ROWS[it][1].toInt(16) } }
    private val RANGE_NAME: Array<String> by lazy { Array(RANGE_ROWS.size) { RANGE_ROWS[it][2] } }

    private val AIRLINE_MAP: Map<String, Pair<String, String?>> by lazy {
        val m = HashMap<String, Pair<String, String?>>(2048)
        for (line in AIRLINES.lineSequence()) {
            if (line.isBlank()) continue
            val p = line.split('|')
            m[p[0]] = Pair(p[1].trim(), p.getOrNull(2)?.trim()?.ifEmpty { null })
        }
        m
    }

    // wiedehopf/tar1090 html/flags.js @958e60e583c4 (ICAO Annex 10 Vol III ch.9 appendix); 197 ranges, territory carve-outs in the UK block omitted
    private val ICAO_RANGES = """
004000,0047FF,Zimbabwe
006000,006FFF,Mozambique
008000,00FFFF,South Africa
010000,017FFF,Egypt
018000,01FFFF,Libya
020000,027FFF,Morocco
028000,02FFFF,Tunisia
030000,0307FF,Botswana
032000,032FFF,Burundi
034000,034FFF,Cameroon
035000,0357FF,Comoros
036000,036FFF,Republic of the Congo
038000,038FFF,Côte d’Ivoire
03E000,03EFFF,Gabon
040000,040FFF,Ethiopia
042000,042FFF,Equatorial Guinea
044000,044FFF,Ghana
046000,046FFF,Guinea
048000,0487FF,Guinea-Bissau
04A000,04A7FF,Lesotho
04C000,04CFFF,Kenya
050000,050FFF,Liberia
054000,054FFF,Madagascar
058000,058FFF,Malawi
05A000,05A7FF,Maldives
05C000,05CFFF,Mali
05E000,05E7FF,Mauritania
060000,0607FF,Mauritius
062000,062FFF,Niger
064000,064FFF,Nigeria
068000,068FFF,Uganda
06A000,06AFFF,Qatar
06C000,06CFFF,Central African Republic
06E000,06EFFF,Rwanda
070000,070FFF,Senegal
074000,0747FF,Seychelles
076000,0767FF,Sierra Leone
078000,078FFF,Somalia
07A000,07A7FF,Eswatini
07C000,07CFFF,Sudan
080000,080FFF,Tanzania
084000,084FFF,Chad
088000,088FFF,Togo
08A000,08AFFF,Zambia
08C000,08CFFF,DR Congo
090000,090FFF,Angola
094000,0947FF,Benin
096000,0967FF,Cabo Verde
098000,0987FF,Djibouti
09A000,09AFFF,Gambia
09C000,09CFFF,Burkina Faso
09E000,09E7FF,São Tomé and Príncipe
0A0000,0A7FFF,Algeria
0A8000,0A8FFF,Bahamas
0AA000,0AA7FF,Barbados
0AB000,0AB7FF,Belize
0AC000,0ADFFF,Colombia
0AE000,0AEFFF,Costa Rica
0B0000,0B0FFF,Cuba
0B2000,0B2FFF,El Salvador
0B4000,0B4FFF,Guatemala
0B6000,0B6FFF,Guyana
0B8000,0B8FFF,Haiti
0BA000,0BAFFF,Honduras
0BC000,0BC7FF,Saint Vincent and the Grenadines
0BE000,0BEFFF,Jamaica
0C0000,0C0FFF,Nicaragua
0C2000,0C2FFF,Panama
0C4000,0C4FFF,Dominican Republic
0C6000,0C6FFF,Trinidad and Tobago
0C8000,0C8FFF,Suriname
0CA000,0CA7FF,Antigua and Barbuda
0CC000,0CC7FF,Grenada
0D0000,0D7FFF,Mexico
0D8000,0DFFFF,Venezuela
100000,1FFFFF,Russia
201000,2017FF,Namibia
202000,2027FF,Eritrea
300000,33FFFF,Italy
340000,37FFFF,Spain
380000,3BFFFF,France
3C0000,3FFFFF,Germany
400000,43FFFF,United Kingdom
440000,447FFF,Austria
448000,44FFFF,Belgium
450000,457FFF,Bulgaria
458000,45FFFF,Denmark
460000,467FFF,Finland
468000,46FFFF,Greece
470000,477FFF,Hungary
478000,47FFFF,Norway
480000,487FFF,Netherlands
488000,48FFFF,Poland
490000,497FFF,Portugal
498000,49FFFF,Czechia
4A0000,4A7FFF,Romania
4A8000,4AFFFF,Sweden
4B0000,4B7FFF,Switzerland
4B8000,4BFFFF,Turkey
4C0000,4C7FFF,Serbia
4C8000,4C87FF,Cyprus
4CA000,4CAFFF,Ireland
4CC000,4CCFFF,Iceland
4D0000,4D07FF,Luxembourg
4D2000,4D27FF,Malta
4D4000,4D47FF,Monaco
500000,5007FF,San Marino
501000,5017FF,Albania
501800,501FFF,Croatia
502800,502FFF,Latvia
503800,503FFF,Lithuania
504800,504FFF,Moldova
505800,505FFF,Slovakia
506800,506FFF,Slovenia
507800,507FFF,Uzbekistan
508000,50FFFF,Ukraine
510000,5107FF,Belarus
511000,5117FF,Estonia
512000,5127FF,North Macedonia
513000,5137FF,Bosnia and Herzegovina
514000,5147FF,Georgia
515000,5157FF,Tajikistan
516000,5167FF,Montenegro
600000,6007FF,Armenia
600800,600FFF,Azerbaijan
601000,6017FF,Kyrgyzstan
601800,601FFF,Turkmenistan
680000,6807FF,Bhutan
681000,6817FF,Micronesia, Federated States of
682000,6827FF,Mongolia
683000,6837FF,Kazakhstan
684000,6847FF,Palau
700000,700FFF,Afghanistan
702000,702FFF,Bangladesh
704000,704FFF,Myanmar
706000,706FFF,Kuwait
708000,708FFF,Laos
70A000,70AFFF,Nepal
70C000,70C7FF,Oman
70E000,70EFFF,Cambodia
710000,717FFF,Saudi Arabia
718000,71FFFF,South Korea
720000,727FFF,North Korea
728000,72FFFF,Iraq
730000,737FFF,Iran
738000,73FFFF,Israel
740000,747FFF,Jordan
748000,74FFFF,Lebanon
750000,757FFF,Malaysia
758000,75FFFF,Philippines
760000,767FFF,Pakistan
768000,76FFFF,Singapore
770000,777FFF,Sri Lanka
778000,77FFFF,Syria
780000,7BFFFF,China
789000,789FFF,Hong Kong
7C0000,7FFFFF,Australia
800000,83FFFF,India
840000,87FFFF,Japan
880000,887FFF,Thailand
888000,88FFFF,Viet Nam
890000,890FFF,Yemen
894000,894FFF,Bahrain
895000,8957FF,Brunei
896000,896FFF,United Arab Emirates
897000,8977FF,Solomon Islands
898000,898FFF,Papua New Guinea
899000,8997FF,Taiwan
8A0000,8A7FFF,Indonesia
900000,9007FF,Marshall Islands
901000,9017FF,Cook Islands
902000,9027FF,Samoa
A00000,AFFFFF,United States
C00000,C3FFFF,Canada
C80000,C87FFF,New Zealand
C88000,C88FFF,Fiji
C8A000,C8A7FF,Nauru
C8C000,C8C7FF,Saint Lucia
C8D000,C8D7FF,Tonga
C8E000,C8E7FF,Kiribati
C90000,C907FF,Vanuatu
C91000,C917FF,Andorra
C92000,C927FF,Dominica
C93000,C937FF,Saint Kitts and Nevis
C94000,C947FF,South Sudan
C95000,C957FF,Timor-Leste
C97000,C977FF,Tuvalu
E00000,E3FFFF,Argentina
E40000,E7FFFF,Brazil
E80000,E80FFF,Chile
E84000,E84FFF,Ecuador
E88000,E88FFF,Paraguay
E8C000,E8CFFF,Peru
E90000,E90FFF,Uruguay
E94000,E94FFF,Bolivia
F00000,F07FFF,ICAO (temporary)
F09000,F097FF,ICAO (special use)
"""

    // unverified: jpatokal/openflights data/airlines.dat @f1d8bc2c0df1, ICAO col, active=Y; 2017-era snapshot, names/countries as the source states them
    private val AIRLINES = """
AAA|Ansett Australia|Australia
AAF|Aigle Azur|France
AAH|Aloha Airlines|United States
AAL|American Airlines|United States
AAN|Amsterdam Airlines|Netherlands
AAQ|Copterline|Finland
AAR|Asiana Airlines|Republic of Korea
AAS|Askari Aviation|Pakistan
AAW|Afriqiyah Airways|Libya
AAY|Allegiant Air|United States
ABD|Air Atlanta Icelandic|Iceland
ABI|Aviabus|Russia
ABL|Air Busan|Republic of Korea
ABQ|Airblue|Pakistan
ABS|Transwest Air|Canada
ABY|Air Arabia|United Arab Emirates
ACA|Air Canada|Canada
ACI|Air Caledonie International|France
ACP|Astral Aviation|Kenya
ADE|Ada Air|Albania
ADH|Air One|Italy
ADO|Hokkaido International Airlines|Japan
ADR|Adria Airways|Slovenia
AEA|Air Europa|Spain
AEB|Aero Benin|Benin
AEE|Aegean Airlines|Greece
AEL|Air Europe|Italy
AER|Alaska Central Express|United States
AES|ACES Colombia|Colombia
AEU|Astraeus|United Kingdom
AEW|Aerosvit Airlines|Ukraine
AEY|Air Italy|Italy
AFG|Ariana Afghan Airlines|Afghanistan
AFL|Aeroflot Russian Airlines|Russia
AFR|Air France|France
AGV|Air Glaciers|Switzerland
AGX|Aviogenex|Serbia
AHO|Air Hamburg (AHO)|Germany
AHY|Azerbaijan Airlines|Azerbaijan
AIA|Avies|Estonia
AIC|Air India Limited|India
AIO|United States Air Force|United States
AIQ|Thai AirAsia|Thailand
AIR|Airlift International|United States
AIZ|Arkia Israel Airlines|Israel
AJM|Air Jamaica|Jamaica
AJX|Air Japan|Japan
AKA|Air Korea Co. Ltd.|Republic of Korea
AKL|Air Kiribati|Kiribati
ALK|SriLankan Airlines|Sri Lanka
ALO|Allegheny Commuter Airlines|United States
AMC|Air Malta|Malta
AML|Air Malawi|Malawi
AMT|ATA Airlines|United States
AMU|Air Macau|Macao
AMV|AMC Airlines|Egypt
AMX|AeroMéxico|Mexico
ANA|All Nippon Airways|Japan
ANE|Air Nostrum|Spain
ANG|Air Niugini|Papua New Guinea
ANK|Air Nippon|Japan
ANO|Airnorth|Australia
ANT|Air North Charter - Canada|Canada
ANU|Andalus Lineas Aereas|Spain
ANZ|Air New Zealand|New Zealand
APW|Arrow Air|United States
ARD|Aerocondor|Portugal
ARF|Aero Flight|Germany
ARG|Aerolineas Argentinas|Argentina
ARU|Aruba Airlines|Aruba
ASA|Alaska Airlines|
ASD|Air Sinai|Egypt
ASH|Mesa Airlines|United States
ASL|Air Serbia|Serbia
ASQ|Atlantic Southeast Airlines|United States
ASZ|Astrakhan Airlines|Russia
ATC|Air Tanzania|Tanzania
ATM|Airlines Of Tasmania|Australia
AUA|Austrian Airlines|Austria
AUB|Augsburg Airways|Germany
AUH|Abu Dhabi Amiri Flight|United Arab Emirates
AUI|Ukraine International Airlines|Ukraine
AUL|Aeroflot-Nord|Russia
AUR|Aurigny Air Services|United Kingdom
AUT|Austral Lineas Aereas|Argentina
AVA|Avianca - Aerovias Nacionales de Colombia|
AVN|Air Vanuatu|Vanuatu
AWA|Asia Wings|Kazakhstan
AWE|America West Airlines|United States
AWI|Air Wisconsin|United States
AWM|Asian Wings Airways|Burma
AWQ|Indonesia AirAsia|Indonesia
AWU|Aeroline GmbH|Germany
AWW|Air Wales|United Kingdom
AXB|Air India Express|India
AXC|Indochina Airlines|Vietnam
AXE|Air Explore|Slovakia
AXL|Air Exel|Netherlands
AXM|AirAsia|Malaysia
AXZ|Aereonautica militare|Italy
AYZ|Atlant-Soyuz Airlines|Russia
AZA|Alitalia|Italy
AZN|Amaszonas|Bolivia
AZU|Azul|Brazil
AZW|Air Zimbabwe|Zimbabwe
BAG|dba|Germany
BAW|British Airways|United Kingdom
BBC|Biman Bangladesh Airlines|Bangladesh
BBG|Bluebird Airways (BZ)|Greece
BBO|Flybaboo|Switzerland
BBR|Santa Barbara Airlines|Venezuela
BCC|BusinessAir|Thailand
BCN|Ocean Air|Mauritania
BCY|CityJet|Ireland
BEE|Flybe|United Kingdom
BER|Air Berlin|Germany
BEU|Bateleur Air|South Africa
BGD|Air Bangladesh|Bangladesh
BGY|Bingo Airways|Poland
BHP|Belair Airlines|Switzerland
BHS|Bahamasair|Bahamas
BIE|Air Mediterranee|France
BIH|British International Helicopters|United Kingdom
BKF|BF-Lento OY|Finland
BKP|Bangkok Airways|Thailand
BLF|Blue1|Finland
BLL|Baltic Airlines|Russia
BLS|Bearskin Lake Air Service|Canada
BLV|Bellview Airlines|Nigeria
BLX|TUIfly Nordic|Sweden
BMA|bmi|United Kingdom
BMI|bmibaby|United Kingdom
BMJ|Bemidji Airlines|United States
BMM|Atlas Blue|Morocco
BMR|British Midland Regional|United Kingdom
BON|Air Bosna|Bosnia and Herzegovina
BOT|Air Botswana|Botswana
BOV|Boliviana de Aviacion (OB)|Bolivia
BPA|Blue Panorama Airlines|Italy
BPS|Budapest Aircraft Services/Manx2|Hungary
BQB|Buquebus Líneas Aéreas|Uruguay
BRG|Bering Air|United States
BRQ|El-Buraq Air Transport|Libya
BRS|Brazilian Air Force|Brazil
BRU|Belavia Belarusian Airlines|Belarus
BSA|Black Stallion Airways|United States
BSX|Bassaka airlines|Cambodia
BTA|ExpressJet|United States
BTI|Air Baltic|Latvia
BTM|Air Batumi|Georgia
BTQ|Boutique Air (Priv)|United States
BTV|Metro Batavia|Indonesia
BUB|Air Bourbon|Reunion
BUR|Air Bucharest|Romania
BUU|Baikotovitchestrian Airlines|American Samoa
BVT|Berjaya Air|Malaysia
BWA|Caribbean Airlines|Trinidad and Tobago
BWG|Blue Wings|Germany
BZE|BRAZIL AIR|Brazil
BZH|Brit Air|France
CAI|Corendon Airlines|Turkey
CAL|China Airlines|Taiwan
CAN|Crest Aviation|United Kingdom
CAP|CanXplorer|Canada
CAW|Comair|South Africa
CAY|Cayman Airways|Cayman Islands
CBG|GX Airlines|China
CCA|Air China|China
CCB|CARICOM AIRWAYS (BARBADOS) INC.|Barbados
CCC|CCML Airlines|Colombia
CCG|Central Connect Airlines|Czech Republic
CCM|Corse-Mediterranee|France
CDG|Shandong Airlines|China
CDN|Canadian Airlines|Canada
CDP|Aero Condor Peru|Peru
CEB|Cebu Pacific|Philippines
CEL|CEIBA Intercontinental|Equatorial Guinea
CEO|Comfort Express Virtual Charters|United States
CES|China Eastern Airlines|China
CEY|Air Century|Dominican Republic
CFE|BA CityFlyer|United Kingdom
CFG|Condor Flugdienst|Germany
CGK|Click Airways|Kyrgyzstan
CGP|Cargo Plus Aviation|United Arab Emirates
CHB|West Air China|China
CHH|Hainan Airlines|China
CHP|Consorcio Aviaxsa|Mexico
CHQ|Chautauqua Airlines|United States
CHW|Charter Air|Austria
CIF|CB Airways UK ( Interliging Flights )|United Kingdom
CIM|Cimber Air|Denmark
CIX|City Connexion Airlines|Burundi
CJC|Colgan Air|United States
CLH|Lufthansa CityLine|Germany
CLI|Calima Aviacion|Spain
CLJ|Cello Aviation|United Kingdom
CLW|Centralwings|Poland
CLX|Cargolux|Luxembourg
CMI|Continental Micronesia|United States
CMP|Copa Airlines|Panama
CNF|Canaryfly|Spain
CNO|SAS Braathens|Norway
COA|Continental Airlines|United States
COE|Comtel Air|Austria
COM|Comair|United States
CPA|Cathay Pacific|Hong Kong SAR of China
CPN|Caspian Airlines|Iran
CPZ|Compass Airlines|United States
CQH|Spring Airlines|China
CQN|Chongqing Airlines|China
CRK|Hong Kong Airlines|Hong Kong SAR of China
CRL|Corsairfly|France
CRO|Crown Airways|United States
CSA|Czech Airlines|Czech Republic
CSC|Sichuan Airlines|China
CSH|Shanghai Airlines|China
CSN|China Southern Airlines|China
CSX|Choice Airways|United States
CSZ|Shenzhen Airlines|China
CTN|Croatia Airlines|Croatia
CUA|China United Airlines|China
CUB|Cubana de Aviación|Cuba
CUD|Air Cudlua|United Kingdom
CVA|Air Chathams|New Zealand
CWK|Comores Airlines|Comoros
CWM|Air Marshall Islands|Marshall Islands
CXA|Xiamen Airlines|China
CYD|Access Air|United States
CYH|Yunnan Airlines|China
CYP|Cyprus Airways|Cyprus
CZV|Via Conectia Airlines|Uruguay
DAH|Air Algerie|Algeria
DAK|First Flying|Japan
DAL|Delta Air Lines|United States
DAO|Daallo Airlines|Djibouti
DAT|Brussels Airlines|Belgium
DBK|Dubrovnik Air|Croatia
DCD|Air 26|Angola
DEA|Delta Aerotaxi|Italy
DHI|Adam Air|Indonesia
DJB|Djibouti Airlines|Djibouti
DKH|Juneyao Airlines|China
DLA|Air Dolomiti|Italy
DLH|Lufthansa|Germany
DME|Royal Flight|Russia
DMO|Domodedovo Airlines|Russia
DNL|Dutch Antilles Express|Netherlands Antilles
DNM|Denim Air|Netherlands
DNV|Aeroflot-Don|Russia
DOA|Dominicana de Aviaci|Dominican Republic
DOB|Dobrolet|Russia
DRD|Air Madrid|Spain
DRK|Druk Air|Bhutan
DRU|Alrosa Mirny Air Enterprise|Russia
DSM|LAN Argentina|Argentina
DSV|Direct Aero Services|Romania
DSY|Dennis Sky|Israel
DTA|TAAG Angola Airlines|Angola
DTR|DAT Danish Air Transport|Denmark
DWA|Dense Airways|United States
DWT|Darwin Airline|Switzerland
DYA|Dynamic Airways|United States
EAA|Eastok Avia|Kyrgyzstan
EAL|European Air Express|Germany
EAV|Eastern Atlantic Virtual Airlines|United States
ECA|Eurocypria Airlines|Cyprus
ECU|Ecuavia|Ecuador
EDW|Edelweiss Air|Switzerland
EEA|Empresa Ecuatoriana De Aviacion|Ecuador
EEU|Eurofly Service|Italy
EFA|Far Eastern Air Transport|Taiwan
EFY|EasyFly|Colombia
EGF|American Eagle Airlines|United States
EGH|BBN-Airways|United Kingdom
EGS|Eagles Airlines|Italy
EHN|East Horizon|Afghanistan
EIA|Evergreen International Airlines|United States
EIN|Aer Lingus|Ireland
EJA|NetJets|United States
ELA|Eastland Air|Australia
ELC|Small Planet Airlines|Lithuania
ELK|ELK Airways|Estonia
ELL|Estonian Air|Estonia
ELO|Eurolot|Poland
ELY|El Al Israel Airlines|Israel
ENJ|Enerjet|Canada
ENY|Envoy Air|United States
ENZ|Jota Aviation|United Kingdom
ERO|Sun D'Or|Israel
ERR|Era Alaska|United States
ERT|Eritrean Airlines|Eritrea
ESK|SkyEurope|Slovakia
ESR|Eastar Jet|South Korea
ETD|Etihad Airways|United Arab Emirates
ETH|Ethiopian Airlines|Ethiopia
EUD|Air Italy Egypt|Egypt
EUV|EuropeSky|Germany
EVA|EVA Air|Taiwan
EVC|Comfort Express Virtual Charters Albany|United States
EWG|Eurowings|Germany
EXS|Jet2.com|United Kingdom
EZA|Eznis Airways|Mongolia
EZE|Eastern Airways|United Kingdom
EZY|easyJet|United Kingdom
FAB|First Air|Canada
FBL|Fly Brasil|Brazil
FCA|First Choice Airways|United Kingdom
FCB|COBALT|Cyprus
FCM|Flybe Finland Oy|Finland
FDB|Fly Dubai|United Arab Emirates
FDD|Feeder Airlines|Sudan
FDX|Federal Express|United States
FEG|FlyEgypt|Egypt
FFM|Firefly|Malaysia
FFT|Frontier Airlines|United States
FFV|Fly540|Kenya
FHE|Hello|Switzerland
FHI|FlyHigh Airlines Ireland (FH)|Ireland
FIF|Air Finland|Finland
FIN|Finnair|Finland
FIX|Airfix Aviation|Finland
FJI|Air Pacific|Fiji
FJM|Fly Jamaica Airways|Jamaica
FKA|Flying kangaroo Airline|Australia
FLB|German Air Force - FLB|Germany
FLG|Pinnacle Airlines|United States
FLI|Atlantic Airways|Faroe Islands
FLT|Flightline|United Kingdom
FLZ|Air Florida|United States
FNA|Norlandair|Iceland
FOS|Formosa Airlines|Taiwan
FOX|FOX Linhas Aereas|Brazil
FPT|FlyPortugal|Portugal
FRE|Freedom Air|United States
FRF|Fly France|France
FRL|Freedom Airlines|United States
FTA|Frontier Flying Service|United States
FVM|Flugfelag Vestmannaeyja|Iceland
FWI|Air Caraïbes|France
FWL|Florida West International Airways|United States
FXI|Air Iceland|Iceland
FXX|Felix Airways|Yemen
FYH|Flyhy Cargo Airlines|Thailand
FYJ|FLYJET|Poland
FZA|Fuzhou Airlines|China
FZW|Fly Africa Zimbabwe|Zimbabwe
GAI|Moskovia Airlines|Russia
GAO|Golden Air|Sweden
GAP|Air Philippines|Philippines
GBA|Gulf Air Bahrain|Bahrain
GBK|Gabon Airlines|Gabon
GBL|GB Airways|United Kingdom
GCA|Grand Cru Airlines|Lithuania
GCR|Tianjin Airlines|China
GDC|Grand China Air|China
GDR|Gadair European Airlines|Spain
GEC|Lufthansa Cargo|Germany
GER|German International Air Lines|Germany
GFA|Gulf Air|Oman
GFG|Georgian National Airlines|Georgia
GFT|Gulfstream International Airlines|United States
GFY|Greenfly|Spain
GHB|Ghana International Airlines|Ghana
GIA|Garuda Indonesia|Indonesia
GIE|Elysian Airlines|Cameroon
GIP|Air Guinee Express|Guinea
GJS|GoJet Airlines|United States
GLA|Great Lakes Airlines|United States
GLG|Aerolineas Galapagos (Aerogal)|Ecuador
GLO|Gol Transportes Aéreos|Brazil
GLP|Globus|Russia
GMI|Germania|Germany
GMR|Golden Myanmar Airlines|Burma
GNN|Georgian International Airlines|Georgia
GOW|Go Air|India
GRL|Air Greenland|Denmark
GSM|Flyglobespan|United Kingdom
GTA|City Airways|Thailand
GTI|Atlas Air|United States
GUY|Air Guyane|French Guiana
GWI|Germanwings|Germany
GWY|USA3000 Airlines|United States
GXG|GermanXL|Germany
GZP|Gazpromavia|Russia
HAG|Hageland Aviation Services|United States
HAL|Hawaiian Airlines|United States
HAM|Haiti Ambassador Airlines|Haiti
HAY|Hamburg Airways|Germany
HBH|Hebei Airlines|China
HBR|Hebradran Air Services|United Kingdom
HCC|Holidays Czech Airlines|Czech Republic
HCW|Star1 Airlines|Lithuania
HDA|Dragonair|
HEJ|Hellas Jet|Greece
HER|Hex'Air|France
HFR|Heli France|France
HHI|Hamburg International|Germany
HKE|Hong Kong Express Airways|Hong Kong SAR of China
HLF|Hapagfly|Germany
HLX|TUIfly|Germany
HMR|North American Charters|Canada
HNX|Hankook Airline|South Korea
HPY|Happy Air|Thailand
HRM|Hermes Airlines|Greece
HSK|Sky Europe Airlines|Slovakia
HTH|Helitt Líneas Aéreas|Spain
HVK|Turkish Air Force|Turkey
HVN|Vietnam Airlines|Vietnam
HWY|Highland Airways|United Kingdom
HYM|Himalayan Airlines|Nepal
HZA|Horizon Airlines|Australia
IAA|Indonesian Airlines|Indonesia
IAC|Indian Airlines|India
IAM|Aeronautica Militare|Italy
IAW|Iraqi Airways|Iraq
IBB|Binter Canarias|Spain
IBE|Iberia Airlines|Spain
IBK|Norwegian Air International (D8)|Norway
IBS|Iberia Express|Spain
IBU|Indigo|United States
IBX|Ibex Airlines|Japan
ICE|Icelandair|Iceland
ICL|CAL Cargo Air Lines|Israel
IDS|Indonesia Sky|Indonesia
IDX|Indonesa Air Aisa X|Indonesia
IGO|IndiGo Airlines|India
IIA|AIR INDOCHINE|Vietnam
IIR|INAVIA Internacional|Argentina
IKA|Itek Air|Kyrgyzstan
ILN|Interair South Africa|South Africa
IMP|Hellenic Imperial Airways|Greece
INE|International Europe|Spain
IPV|Parmiss Airlines (IPV)|Iran
IRA|Iran Air|Iran
IRC|Iran Aseman Airlines|Iran
IRK|Kish Air|Iran
IRM|Mahan Air|Iran
ISK|Intersky|Austria
ISR|Israir|Israel
ISS|Meridiana|Italy
ISV|Islena De Inversiones|Honduras
ISW|Islas Airways|Spain
ISX|Island Spirit|Iceland
ITK|Interlink Airlines|South Africa
ITX|Imair Airlines|Azerbaijan
IWA|Apache Air|United States
IWD|Iberworld|Spain
IXO|OCEAN AIR CARGO|India
IYE|Yemenia|Yemen
JAA|Japan Asia Airways|Japan
JAB|Air Bagan|Myanmar
JAF|Jetairfly|Belgium
JAI|Jet Airways|India
JAL|Japan Airlines|Japan
JAS|Japan Air System|Japan
JAZ|JALways|Japan
JBA|Helijet|Canada
JBU|JetBlue Airways|United States
JEF|Jetflite|Finland
JET|Wind Jet|Italy
JEX|JAL Express|Japan
JFU|Jet4You|Morocco
JGN|Jagson Airlines|India
JJA|Jeju Air|Republic of Korea
JJP|Jetstar Japan|Japan
JKK|Spanair|Spain
JNA|Jin Air|South Korea
JOR|Blue Air|Romania
JOY|Joy Air|China
JPU|Jupiter Airlines|United Arab Emirates
JRB|Jc royal.britannica|United Kingdom
JSA|Jetstar Asia Airways|Singapore
JSR|Jusur airways|Egypt
JST|Jetstar Airways|Australia
JTA|Japan Transocean Air|Japan
JTO|Jettor Airlines|Hong Kong
JZA|Air Canada Jazz|Canada
JZR|Jazeera Airways|Kuwait
KAC|Kuwait Airways|Kuwait
KAL|Korean Air|Republic of Korea
KAP|Cape Air|United States
KBR|KoralBlue Airlines|Egypt
KBZ|Air KBZ|Burma
KCU|Skyline Ulasim Ticaret A.S.|Turkey
KDA|Kendell Airlines|Australia
KEA|Korea Express Air|South Korea
KEN|Kenmore Air|United States
KFR|Kingfisher Airlines|India
KGL|Kogalymavia Air Company|Russia
KGO|Korongo Airlines|Congo (Kinshasa)
KHB|Dalavia|Russia
KHK|Kharkiv Airlines|Ukraine
KIL|Kuban Airlines|Russia
KIN|Kinloss Flying Training Unit|United Kingdom
KIS|Contact Air|Germany
KJC|Krasnojarsky Airlines|Russia
KKK|Atlasjet|Turkey
KLC|KLM Cityhopper|Netherlands
KLM|KLM Royal Dutch Airlines|Netherlands
KLS|Kal Star Aviation|Indonesia
KMF|Kam Air|Afghanistan
KND|Kan Air|Thailand
KNE|Nas Air|Saudi Arabia
KNI|KD Avia|Russia
KOL|SOCHI AIR|Russia
KOQ|Kostromskie avialinii|Russia
KOR|Air Koryo|Democratic People's Republic of Korea
KQA|Kenya Airways|Kenya
KRP|Carpatair|Romania
KRY|Russkie Krylya|Russia
KSM|Kosmos|Russia
KSY|KSY|Greece
KSZ|Sunrise Airways|Haiti
KUH|Kush Air|South Sudan
KYA|Alghanim|United States
KZK|Air Kazakhstan|Kazakhstan
KZR|Air Astana|Kazakhstan
KZU|Kuzu Airlines Cargo|Turkey
LAA|Libyan Arab Airlines|Libya
LAJ|British Mediterranean Airways|United Kingdom
LAM|Linhas A|Mozambique
LAN|LAN Airlines|Chile
LAP|TAM Mercosur|Paraguay
LAV|AlbaStar|Spain
LBC|Albanian Airlines|Albania
LBL|Line Blue|Germany
LBT|Nouvel Air Tunisie|Tunisia
LDA|Lauda Air|Austria
LFA|Air Alfa|Turkey
LGL|Luxair|Luxembourg
LGW|Luftfahrtgesellschaft Walter|Germany
LHN|Express One International|United States
LIA|Leeward Islands Air Transport|Antigua and Barbuda
LIL|FlyLal|Lithuania
LIX|LionXpress|Cameroon
LJJ|Luchsh Airlines|Russia
LLC|FlyLAL Charters|Lithuania
LLM|Yamal Airlines|Russia
LMM|LCM AIRLINES|Russia
LMU|AlMasria Universal Airlines|Egypt
LNE|Aerolane|Ecuador
LNI|Lion Mentari Airlines|Indonesia
LOC|Locair|United States
LOF|Trans States Airlines|United States
LOO|LSM Airlines|Russia
LOT|LOT Polish Airlines|Poland
LPE|LAN Peru|Peru
LRC|LACSA|Costa Rica
LTC|LatCharter|Latvia
LTD|Southern Airways Express|United States
LTE|LTE International Airways|Spain
LTO|LTU Austria|Austria
LTR|Lufttransport|Norway
LTU|Air Lituanica|Lithuania
LTY|Liberty Airways|United States
LUR|Atlantis European Airways|Armenia
LXP|LAN Express|Chile
LXR|Air Luxor|Portugal
LZB|Bulgaria Air|Bulgaria
MAA|MasAir|Mexico
MAC|Malta Air Charter|Malta
MAH|Malév|Hungary
MAI|Mauritania Airlines International|Mauritania
MAK|MAT Macedonian Airlines|Macedonia
MAL|Morningstar Air Express|Canada
MAS|Malaysia Airlines|Malaysia
MAU|Air Mauritius|Mauritius
MAV|Maldivo Airlines|Maldives
MCA|MCA Airlines|Sweden
MCK|Macair Airlines|Australia
MDA|Mandarin Airlines|Taiwan
MDG|Air Madagascar|Madagascar
MDL|Mandala Airlines|Indonesia
MDO|Domenican Airlines|Dominican Republic
MDP|Medallion Air|Romania
MDV|Moldavian Airlines|Moldova
MDW|Midway Airlines|United States
MEA|Middle East Airlines|Lebanon
MEP|Midwest Airlines|United States
MES|Mesaba Airlines|United States
MGL|MIAT Mongolian Airlines|Mongolia
MGX|Montenegro Airlines|Montenegro
MIC|Mint Airways|Spain
MJG|Michael Airlines|Puerto Rico
MJP|Air Majoro|Peru
MJX|Euroline|Georgia
MKD|MAT Airways|Macedonia
MKG|Air Mekong|Vietnam
MKU|Island Air (WP)|United States
MLA|40-Mile Air|United States
MLD|Air Moldova|Moldova
MMM|Myanmar Airways International|Myanmar
MNA|Merpati Nusantara Airlines|Indonesia
MNB|MNG Airlines|Turkey
MNO|Mango|South Africa
MNP|Spirit of Manila Airlines|Philippines
MON|Monarch Airlines|United Kingdom
MOV|VIM Airlines|Russia
MPD|Air Plus Comet|Spain
MPE|Canadian North|Canada
MPH|Martinair|Netherlands
MRS|Marusya Airways|Russia
MSE|EgyptAir Express|Egypt
MSI|Motor Sich|Ukraine
MSR|Egyptair|Egypt
MTW|Mauritania Airways|Mauritania
MVD|Kavminvodyavia|Russia
MWA|Midwest Airlines (Egypt)|Egypt
MWI|Malaysia Wings|Malaysia
MXA|Mexicana de Aviaci|Mexico
MXD|Malindo Air|Malaysia
MXI|MexicanaLink|Mexico
MXL|Maxair|Sweden
MYA|Myflug|Iceland
MYD|Maya Island Air|Belize
MYP|Mann Yadanarpon Airlines|Burma
MYT|MyTravel Airways|United Kingdom
NAK|Arik Niger|Niger
NAS|Nasair|Eritrea
NAX|Norwegian Air Shuttle|Norway
NCF|Norfolk County Flight College|United Kingdom
NCR|National Air Cargo|United States
NDC|FlyNordic|Sweden
NDN|Transportes Aereos Cielos Andinos|Peru
NEA|New England Airlines|United States
NGB|Nordic Global Airlines|Finland
NIA|Nile Air|Egypt
NIG|Aero Contractors|Nigeria
NJS|National Jet Systems|Australia
NKF|Barents AirLink|Sweden
NKS|Spirit Airlines|United States
NLH|Norwegian Long Haul AS|Norway
NLY|Niki|Austria
NMA|Nesma Airlines|Egypt
NMB|Air Namibia|Namibia
NMI|Pacific Wings|United States
NOK|Nok Air|Thailand
NSE|SATENA|Colombia
NTJ|NextJet|Sweden
NTM|North American Airlines|Canada
NTW|Nationwide Airlines|South Africa
NVR|Novair|Sweden
NWA|Northwest Airlines|United States
NXB|NEXT Brasil|Brazil
NYT|Yeti Airlines|Nepal
OAB|Orbit Airlines Azerbaijan|Azerbaijan
OAE|Omni Air International|United States
OAI|Orbit International Airlines|United States
OAL|Olympic Airlines|Greece
OAN|Orbit Atlantic Airways|United States
OAR|Orbit Regional Airlines|United States
OAW|Helvetic Airways|Switzerland
OBS|Orbest|Portugal
OBT|Orbit Airlines|United States
OCA|Aserca Airlines|Venezuela
OEA|Orient Thai Airlines|Thailand
OGN|Origin Pacific Airways|New Zealand
OHK|Oasis Hong Kong Airlines|Hong Kong
OHY|Onur Air|Turkey
OLA|Overland Airways|Nigeria
OLS|Sol Lineas Aereas|Argentina
OLT|Ostfriesische Lufttransport|Germany
OMA|Oman Air|Oman
OME|Homer Air|Germany
ONE|Oceanair|Brazil
OOM|Zoom Airlines|Canada
ORB|Orenburg Airlines|Russia
ORC|Orchid Airlines|Australia
ORG|Orenburzhie|Russia
OTG|One Two Go Airlines|Thailand
OTJ|Fly Romania|Romania
OZJ|Ozjet Airlines|Australia
OZW|Skywest Airlines|Australia
PAL|Philippine Airlines|Philippines
PAO|Polynesian Airlines|Samoa
PBA|PB Air|Thailand
PBD|Pobeda|Russia
PCO|Pacific Coastal Airline|Canada
PDC|Potomac Air|United States
PDT|Piedmont Airlines (1948-1989)|United States
PEC|Pacific East Asia Cargo Airlines|Philippines
PEL|Aeropelican Air Services|Australia
PEN|Peninsula Airways|United States
PFL|Pacific Flier|Palau
PGA|Portugalia|Portugal
PGT|Pegasus Airlines|Turkey
PIA|Pakistan International Airlines|Pakistan
PIC|Jetstar Pacific|Vietnam
PLI|Aeroper|Peru
PLR|Northwestern Air|Canada
PMT|PMTair|Cambodia
PMW|Paramount Airways|India
PNR|PAN Air|Spain
POE|Porter Airlines|Canada
POT|Polet|Russia
PPL|Air Pegasus|India
PPW|Royal Phnom Penh Airways|Cambodia
PQW|PanAm World Airways|United States
PRF|Precision Air|Tanzania
PSA|Pacific Island Aviation|United States
PSB|Syrian Pearl Airlines|Syria
PTB|Passaredo Transportes Aereos|Brazil
PTI|Privatair|Switzerland
PUA|PLUNA|Uruguay
PYA|Pouya Air|Iran
PYB|All America BOPY|Paraguay
PZY|Zapolyarie Airlines|Russia
QAX|QatXpress|Qatar
QER|SOCHI AIR CHATER|Russia
QFA|Qantas|Australia
QFZ|Fars Air Qeshm|Iran
QQQ|ENTERair|Poland
QTR|Qatar Airways|Qatar
QXE|Horizon Air|United States
RAB|Rainbow Air (RAI)|United States
RAE|Régional|France
RAM|Royal Air Maroc|Morocco
RAR|Air Rarotonga|Cook Islands
RAW|Royal Airways|United States
RAY|Rainbow Air Canada|Canada
RBA|Royal Brunei Airlines|Brunei
RBG|Air Arabia Egypt|Egypt
RBY|Vision Airlines (V2)|United States
REA|Aer Arann|Ireland
REP|Regional Paraguaya|Paraguay
REU|Air Austral|France
RFJ|Royal Falcon|Jordan
RGG|TransRussiaAirlines|Russia
RIT|Asian Spirit|Philippines
RJA|Royal Jordanian|Jordan
RJD|Rotana Jet|United Arab Emirates
RKA|Air Afrique|Ivory Coast
RLA|Airlinair|France
RLN|Aero Lanka|Sri Lanka
RLU|Rusline|Russia
RLX|Go2Sky|Slovakia
RMK|Simrik Airlines|Nepal
RNA|Nepal Airlines|Nepal
RNE|Air Salone|Sierra Leone
RNV|Armavia|Armenia
RNX|1Time Airline|South Africa
RNY|Rainbow Air US|United States
RON|Nauru Air Corporation|Nauru
ROT|Tarom|Romania
RPA|Republic Airlines|United States
RPB|AeroRep|Colombia
RPH|Republic Express Airlines|Indonesia
RPO|Rainbow Air Polynesia|United States
RRJ|AirRussia|Russia
RSD|Russia State Transport|Russia
RSH|Air Sahara|India
RSI|Air Sunshine|United States
RSJ|RusJet|Russia
RSP|Jet Suite|United States
RSR|Aero-Service|Republic of the Congo
RSU|Aerosur|Bolivia
RSY|I-Fly|Russia
RTE|Aeronorte|Portugal
RUE|Rainbow Air Euro|United Kingdom
RUS|Cirrus Airlines|Germany
RWD|Rwandair Express|Rwanda
RWW|Fly Europa|Spain
RWZ|Red Wings|Russia
RXA|Regional Express|Australia
RXR|REXAIR VIRTUEL|France
RYA|Ryan Air Services|United States
RYN|Ryan International Airlines|United States
RYR|Ryanair|Ireland
RZO|SATA International|Portugal
SAA|South African Airways|South Africa
SAE|SOCHI AIR EXPRESS|Russia
SAI|Shaheen Air International|Pakistan
SAL|Spike Airlines|United States
SAS|Scandinavian Airlines System|Sweden
SAT|SATA Air Acores|Portugal
SAY|ScotAirways|United Kingdom
SBD|Snowbird Airlines|Finland
SBI|S7 Airlines|Russia
SBS|Seaborne Airlines|United States
SCE|Scenic Airlines|United States
SCO|Scoot|Singapore
SCX|Sun Country Airlines|United States
SDI|San Dima Air|United States
SDM|Rossiya-Russian Airlines|Russia
SDR|City Airline|Sweden
SEA|Southeast Air|United States
SEH|Sky Express|Greece
SEJ|Spicejet|India
SEN|Sevenair|Tunisia
SEU|XL Airways France|France
SEY|Air Seychelles|Seychelles
SFJ|Star Flyer|Japan
SGG|Senegal Airlines|Senegal
SGY|Skagway Air Service|United States
SHA|Sharp Airlines|Australia
SHD|Sahara Airlines|Algeria
SIA|Singapore Airlines|Singapore
SIB|Sibaviatrans|Russia
SIH|Skynet Airlines|Ireland
SJM|Svyaz Rossiya|Russia
SJO|Spring Airlines Japan|Japan
SJS|Southjet|United States
SJU|Skyjet Airlines|Uganda
SJY|Sriwijaya Air|Indonesia
SKU|Sky Airline|Chile
SKV|Sky Regional|Canada
SKW|SkyWest|United States
SKX|Skyways Express|Sweden
SKY|Skymark Airlines|Japan
SLI|Aerolitoral|Mexico
SLK|SilkAir|Singapore
SLM|Surinam Airways|Suriname
SMJ|Avient Aviation|Zimbabwe
SMW|Carpatair Flight Training|Romania
SMX|Alitalia Express|Italy
SMY|Sama Airlines|Saudi Arabia
SNB|Sterling Airlines|Denmark
SNC|Air Cargo Carriers|United States
SNJ|Skynet Asia Airways|Japan
SOA|Southern Air Charter|Bahamas
SOL|Solomon Airlines|Solomon Islands
SOU|Southern Airways|United States
SOV|Saratov Aviation Division|Russia
SOZ|Sat Airlines|Kazakhstan
SPI|South Pacific Island Airways|United States
SPM|Air Saint Pierre|France
SQC|Singapore Airlines Cargo|Singapore
SQH|SeaPort Airlines|United States
SRB|Solar Air|Thailand
SRH|Siem Reap Airways|Cambodia
SRN|Sprintair|Poland
SRQ|South East Asian Airlines|Philippines
SRY|ViaAir|United States
SSA|All America US|United States
SSV|Skyservice Airlines|Canada
STP|STP Airways|Sao Tome and Principe
STU|Servicios de Transportes A|Argentina
SUD|Sudan Airways|Sudan
SUW|Interavia Airlines|Russia
SVA|Saudi Arabian Airlines|Saudi Arabia
SVG|SVG Air|Saint Vincent and the Grenadines
SVR|Ural Airlines|Russia
SWA|Southwest Airlines|United States
SWD|Southern Winds Airlines|Argentina
SWM|Sky Angkor Airlines (ZA)|Cambodia
SWR|Swiss International Air Lines|Switzerland
SWU|Swiss European Air Lines|Switzerland
SWV|Swe Fly|Sweden
SXR|Sky Express|Russia
SXS|SunExpress|Turkey
SYL|Aircompany Yakutia|Russia
SYR|Syrian Arab Airlines|Syrian Arab Republic
SYX|Skywalk Airlines|United States
SZB|Aerolineas heredas santa maria|Dominican Republic
SZZ|SUR Lineas Aereas|Argentina
TAE|TAME|Ecuador
TAH|Air Moorea|France
TAK|Tatarstan Airlines|Russia
TAM|TAM Brazilian Airlines|Brazil
TAN|Zanair|Tanzania
TAO|Aeromar|Mexico
TAP|TAP Portugal|Portugal
TAR|Tunisair|Tunisia
TAT|Grupo TACA|Costa Rica
TBZ|TrasBrasil|Brazil
TCF|Shuttle America|United States
TCG|Thai Air Cargo|Thailand
TCV|TACV|Portugal
TCW|Thomas Cook Airlines|Belgium
TCX|Thomas Cook Airlines|United Kingdom
TDK|Transavia Denmark|Denmark
TEZ|Tez Jet Airlines|Kyrgyzstan
TFL|Arkefly|Netherlands
TFN|Norwegian Aviation College|Norway
TGN|Trigana Air Service|Indonesia
TGW|Tiger Airways|Singapore
TGZ|Georgian Airways|Georgia
THA|Thai Airways International|Thailand
THI|TransHolding|Brazil
THK|Turk Hava Kurumu Hava Taksi Isletmesi|Turkey
THS|TransBrasil Airlines|Brazil
THT|Air Tahiti Nui|France
THY|Turkish Airlines|Turkey
TIB|TRIP Linhas A|Brazil
TIL|Tajikistan International Airlines|Tajikistan
TJA|T.J. Air|United States
TJT|Twin Jet|France
TKS|Tomsk-Avia|Russia
TLA|Translift Airways|Ireland
TMA|Trans Mediterranean Airlines|Lebanon
TNA|TransAsia Airways|Taiwan
TNM|Tiara Air|Aruba
TNS|Transilvania|Romania
TNU|TransNusa Air|Indonesia
TOK|Airlines PNG|Papua New Guinea
TOM|Thomsonfly|United Kingdom
TOS|Tropic Air|Belize
TPA|TAMPA|Colombia
TRA|Transavia Holland|Netherlands
TRK|Turkuaz Airlines|Turkey
TRS|AirTran Airways|United States
TSC|Air Transat|Canada
TSO|Transaero Airlines|Russia
TTZ|Transair|Canada
TUA|Turkmenistan Airlines|Turkmenistan
TUI|Tuninter|Tunisia
TUR|ATUR|Ecuador
TUS|ABSA - Aerolinhas Brasileiras|Brazil
TVF|Transavia France|France
TVJ|Thai Vietjet Air|Thailand
TVS|Travel Service|Czech Republic
TWB|Tway Airlines|South Korea
TWD|Turkish Wings Domestic|Turkey
TWN|Avialeasing Aviation Company|Uzbekistan
TXW|Texas Wings|United States
TYR|Tyrolean Airways|Austria
TYS|TransHolding System|Brazil
UAC|United Air Charters|Zimbabwe
UAE|Emirates|United Arab Emirates
UAL|United Airlines|United States
UAT|Ukraine Atlantic|Ukraine
UAY|University of Birmingham Air Squadron (RAF)|United Kingdom
UBA|Myanma Airways|Myanmar
UBD|United Airways|Bangladesh
UBG|US-Bangla Airlines|Bangladesh
UCA|CommutAir|United States
UDC|DonbassAero|Ukraine
UDN|Dniproavia|Ukraine
UGX|East African|Uganda
UIA|Uni Air|Taiwan
UJX|AtlasGlobal Ukraine|Ukraine
UKM|UM Airlines|Ukraine
UMK|Yuzhmashavia|Ukraine
UPA|Air Foyle|United Kingdom
UPS|United Parcel Service|United States
URN|Turan Air|Azerbaijan
USA|US Airways|United States
USH|US Helicopter|United States
UTA|UTair Aviation|Russia
UTY|Alliance Airlines|Australia
UWW|LSM International|Russia
UZB|Uzbekistan Airways|Uzbekistan
VAS|ATRAN Cargo Airlines|Russian Federation
VAX|V Air|Taiwan
VBW|Air Burkina|Burkina Faso
VCV|Conviasa|Venezuela
VDA|Volga-Dnepr Airlines|Russia
VEX|Virgin Express|Belgium
VFC|Vasco Air|Vietnam
VGN|Virgin Nigeria Airways|Nigeria
VIA|VIA Líneas Aéreas|Argentina
VIM|Air VIA|Bulgaria
VIR|Virgin Atlantic Airways|United Kingdom
VIS|Vision Air International|Pakistan
VJC|VietJet Air|Vietnam
VKH|Viking Hellas|Greece
VKJ|VickJet|France
VLE|Volare Airlines|Italy
VLG|Vueling Airlines|Spain
VLK|Vladivostok Air|Russia
VLM|VLM Airlines|Belgium
VLO|Varig Log|Brazil
VLU|Valuair|Singapore
VNP|Virgin Pacific|Fiji
VOE|VOLOTEA Airways|Spain
VOI|Volaris|Mexico
VOO|Volotea|Spain
VOZ|Virgin Australia|Australia
VQI|Flyme (VP)|Maldives
VRD|Virgin America|United States
VRN|VRG Linhas Aereas|Brazil
VSP|VASP|Brazil
VSV|Scat Air|Kazakhstan
VTA|Air Tahiti|French Polynesia
VTI|Air Vistara|India
VUE|AD Aviation|United Kingdom
VUN|Air Ivoire|Ivory Coast
VVC|VivaColombia|Colombia
VVM|Viva Macau|Macao
VWA|Virginwings|Germany
WAJ|AirAsia Japan|Japan
WAL|Western Airlines|United States
WAU|Wizz Air Ukraine|Ukraine
WBA|Finncomm Airlines|Finland
WEB|WebJet Linhas A|Brazil
WEN|WestJet Encore|Canada
WER|AeroWorld|Russia
WFX|Westfalia Express VA|Germany
WIF|Widerøe|Norway
WJA|WestJet|Canada
WLC|Welcome Air|Austria
WOA|World Airways|United States
WON|Wings Air|Indonesia
WOW|Air Southwest|United Kingdom
WRC|Wind Rose Aviation|Ukraine
WSS|World Scale Airlines|United States
WTA|Africa West|Togo
WTJ|Whitejets|Brazil
WVL|Wizz Air Hungary|Bulgaria
WZZ|Wizz Air|Hungary
XAN|Southjet cargo|United States
XAU|XAIR USA|United States
XAX|AirAsia X|Malaysia
XBM|CBM America|United States
XEL|Excel Charter|United Kingdom
XLA|Excel Airways|United Kingdom
XOJ|XOJET|United States
XPT|XPTO|Portugal
XSR|Executive AirShare|United States
YCC|Ciel Canadien|Canada
YCP|Canadian National Airways|Canada
YEL|Yellowtail|United States
YEP|YES Airways|Poland
YZZ|LSM AIRLINES|Russia
ZCS|Southjet connect|United States
ZNA|Zenith International Airline|Thailand
ZTF|Mongolian International Air Lines|Mongolia
ZTT|ZABAIKAL AIRLINES|Russia
ZXY|Japan Regio|Japan
ZZZ|Zabaykalskii Airlines|Russia
"""
}
