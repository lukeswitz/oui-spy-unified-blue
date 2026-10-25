package com.rootdowndigital.ouispy.wifiadapter

internal object Rtl433Categories {
    val ALL_CATEGORIES = listOf("tpms", "weather", "meter", "security", "fob", "environmental")

    val BY_CATEGORY: Map<String, Set<Rtl433Decoder>> = mapOf(
        "tpms" to setOf(
            SchraderEG53MA4, SchraderMRXBC5A4, SchraderNIS315G3, SchraderSMD3MA4, Schraeder, Steelmate,
            TmpsGearHive, TpmsAbarth124, TpmsAirpuxem, TpmsAve, TpmsBmw, TpmsBmwg3,
            TpmsCitroen, TpmsEezrv, TpmsElantra2012, TpmsFord, TpmsGm, TpmsHonda,
            TpmsHyundaiVdo, TpmsImarsT240, TpmsJansite, TpmsJansiteSolar, TpmsJansiteTy468, TpmsJansiteTy588,
            TpmsJeep, TpmsKia, TpmsMercedesBenz, TpmsNissan, TpmsPmv107j, TpmsPorsche,
            TpmsRenault, TpmsRenault0435r, TpmsSchraderMotorcycle, TpmsSefisM3, TpmsSmartire, TpmsToyota,
            TpmsTruck, TpmsTrwFsk, TpmsTrwOok, TpmsTyreguard400,
        ),
        "meter" to setOf(
            AntAntplus, ApatorMetraEitn30, ApatorMetraErm30, AradMsMeter, BadgerOrion, Blueline,
            Bm5, Cmr113, CurrentCost, Ec3k, Ecodhome, Ecoeye,
            EfergyE2Classic, EfergyOptical, ElsterPowerMeter, ElsterPowerMeter2, ElvEm1000, Emontx,
            ErtIdm, ErtNetidm, ErtScm, EsaEnergy, EsicEmt7110, Flowis,
            GeoMinim, Gridstream192, Gridstream384, Gridstream96, IkeaSparsnas, MBusModeCT,
            MBusModeCTDownlink, MBusModeF, MBusModeR, MBusModeS, MarlecSolar, MuellerHotrod,
            NeptuneR900, NeptuneR900bcd, Norgo, OrionEndpoint, OrionEndpoint2020, Radian,
            RadioheadAsk, RevoltNc5462, RevoltZx7717, Rfm69LowpowerlabMoteino, Rfxmeter, Scmplus,
            SilverSpringMesh,
        ),
        "security" to setOf(
            Cavius, CaviusDoor, ChamberlainCwpirc, Chuango, ElroDb286a, GenericMotion,
            Honeywell, HoneywellWdb, Interlogix, Kerui, KiddeSmoke, Olympia9571,
            Quhwa, RiscoAgility, SimplisafeGen3, SmokeGs558, SsSensor, TwogigKey2e,
            VisonicPowercode, Vivint, X10Sec, YaleHsa,
        ),
        "fob" to setOf(
            Akhan100F14, AlpsFwb1u545CarRemote, Astrostart2000, AudiovoxProOe3b, BaldrHcs528arf, Blyss,
            BrennenstuhlRcs2044, Cardin, Ced7000, ChryslerCarRemote, CodeAlarmFrdpc2000CarRemote, Compustar1wg3r,
            ContinentalCarRemote, CttLifePowerHybrid, DeltadoreX3d, DickertPwm, Directv, DishRemote63,
            EberleInstat868r1, Elero, FlexDecoder, Fordremote, Fs20, FslScoreboard,
            FunkbusRemote, GeColoreffects, GenericRemoteSc226x, GmCarRemote, Hcs200, Hcs200Fsk,
            Hcs361Txwak0Bsel1, Hcs361Txwak1Bsel0, Hcs361Txwak1Bsel1, Hcs361TxwakBsel0, Hcs361Vpwm1Bsel0, Hcs361Vpwm1Bsel1,
            Hcs362Mc, Hcs362Pwm, HomeleadHg9901, HondaKeyfob, Hondaremote, HoneywellWdbFsk,
            Ht680, IbisBeacon, Insteon, Intertechno, Jasco, LightwaveRf,
            Markisol, MartecMplcd, McpowerKinetic, Megacode, Newkaku, Nexa,
            NiceFlorS, NidecCarRemote, OpelMokka, Proflame2, Proove, Quinetic,
            RainpointHcs012arf, RegencyFan, Rftech, Rojaflex, SecplusV1, SecplusV2,
            Siemens5wy72xxCarRemote, Silvercrest, SixScTwoCarRemote, SomfyIohc, SomfyRts, SrsmithPoolSrs2cTx,
            Tr502msv, Universalfanctrl, Waveman, X10Rf,
        ),
        "environmental" to setOf(
            Abmt, Acurite01185m, Bresser7in1, BresserGarden, BresserLeakage, BurnhardBbq,
            DanfossCfr, EnoceanErp1, GasmateBa1008, Govee, GoveeH5054, GoveeH5059,
            GoveeH5112, GoveeH5310, GrillThermometer, HoneywellCm921, MaverickEt73, MaverickEt73x,
            MaverickXr30, MaverickXr50, OilSmart, OilStandard, OilStandardAsk, OilWatchman,
            OilWatchmanAdvanced, OpusXt300, OriaWa150km, Rainpoint, RosstechDcu706, SensibleLiving,
            Springfield, ThermoproTp11, ThermoproTp12, ThermoproTp211b, ThermoproTp28b, ThermoproTp828b,
            ThermoproTp829b, ThermoproTp86xb, TsFt002, TyphurSyncGold, VaillantVrt340f, WatchmanPlus,
            WattsThermostat, WattsVision, WattsWfhtRf,
        ),
        "weather" to setOf(
            Acurite00275rm, Acurite590tx, Acurite606, Acurite985, Acurite986, AcuriteRain896,
            AcuriteTh, AcuriteTxr, Alectov1, AmbientWeather, AmbientweatherTx8300, AmbientweatherWh31e,
            ArchosTbh, ArexxMl, AtechWs308, Auriol4ld5661, AuriolAft77b2, AuriolAfw2a1,
            AuriolAhfl, AuriolHg02832, AuriolHg04641a, BaldrRain, BaldrTherm, Bresser3ch,
            Bresser5in1, Bresser6in1, BresserLightning, BresserSt1005h, BtRain, CalibeurRf104,
            CelsiaCzc1, CompanionWtr001, Cotech367900, Cotech367959, CotechFt0203, DigitechXc0324,
            Ecowitt, ElsnerSolexa, ElvWs2000, Emax, EmosE6016, EmosE6016Rain,
            En2058, EsperanzaEws, EsunEn2053, Eurochron, EurochronEfth800, FineoffsetWH0530,
            FineoffsetWH2, FineoffsetWH25, FineoffsetWH51, FineoffsetWh1050, FineoffsetWh1080, FineoffsetWh1080Fsk,
            FineoffsetWh31l, FineoffsetWh43, FineoffsetWh45, FineoffsetWh46, FineoffsetWh52, FineoffsetWh55,
            FineoffsetWh5rb, FineoffsetWn34, FineoffsetWs80, FineoffsetWs85, FineoffsetWs90, Florabest,
            Ft004b, GeevonTx16, GeevonTx19, GenericTemperatureSensor, GtTmbbq05, GtWt02,
            GtWt03, HanwellMl4000, HidekiTs04, HolmanWs5029pcm, HolmanWs5029pwm, HolmanWs5029pwmOok,
            Infactory, InkbirdIth20r, Kedsum, Klimalogg, Kw9015b, LacrosseBreezepro,
            LacrosseR1, LacrosseTh3, LacrosseTx141x, LacrosseTx22uit, LacrosseTx22uitOok, LacrosseTx29,
            LacrosseTx31u, LacrosseTx34, LacrosseTx35, LacrosseWr1, LacrosseWs6868Tx231rw, LacrosseWs6868Tx232th,
            LacrosseWs7000, Lacrossetx, Lacrossews, Mebus433, MissilMl0757, NetatmoThw,
            Nexus, NexusSauna, Omni, OregonScientific, OregonScientificSl109h, OregonScientificV1,
            OregonScientificWmr500, PhilipsAj3650, PhilipsAj7010, Prologue, Rubicson, Rubicson48659,
            RubicsonPool48942, S3318p, SainlogicSa8, Schou72543Rain, SharpSpc775, ShenzhenWaleWlTh6r,
            SolightTe44, TelldusFt0385r, Tfa141504v2, Tfa303151, Tfa303196, Tfa303221,
            Tfa303307, Tfa30390x, TfaDrop303233, TfaMarbella, TfaPoolThermometer, TfaTwinPlus303049,
            ThermoproTx2, ThermoproTx2c, ThermoproTx7b, Thermor, ThermorA6n132tx, Ttx201,
            VaunoEn8822c, Vevor7in1, WallargeCltx001, Wec2103, WgPb12v1, Ws2032,
            Wssensor, Wt1024, Wt450,
        ),
    )

    fun forCategories(cats: Set<String>): Set<Rtl433Decoder> =
        cats.flatMap { BY_CATEGORY[it] ?: emptySet() }.toSet()
}
