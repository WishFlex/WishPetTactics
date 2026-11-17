local ADDON_NAME, ns = ...

local FuzzySearch = {}
ns.FuzzySearch = FuzzySearch

local byte = string.byte
local sub = string.sub
local find = string.find
local gmatch = string.gmatch
local strlower = strlower
local strtrim = strtrim

-- Pinyin syllable groups (Simplified + common Traditional Chinese characters)
-- Built once at load time into O(1) lookup tables PINYIN_FULL[ch] and PINYIN_INIT[ch].
local PINYIN_SYLLABLE_GROUPS = {
    a = "啊阿", ai = "哀皑癌蔼矮艾碍爱埃哎唉", an = "安氨俺按暗岸胺案鞍闇", ang = "肮昂盎", ao = "凹敖熬翱袄傲奥懊澳",
    ba = "八巴芭扒叭吧笆疤跋靶把耙坝霸罢爸", bai = "白柏百摆佰败拜稗", ban = "斑班般颁板版扮拌伴瓣半办绊",
    bang = "邦帮梆榜膀绑棒磅傍谤", bao = "包胞褒剥薄雹保堡饱宝抱报暴豹鲍爆", bei = "杯碑悲卑北辈背贝钡倍狈备惫焙被貝備",
    ben = "奔苯本笨", beng = "崩绷甭泵蹦", bi = "逼鼻比鄙笔彼碧蔽毕毙毖币庇痹闭敝弊必辟壁臂避陛幣畢閉",
    bian = "鞭边编贬扁便变卞辨辩辫遍邊變", biao = "标彪膘表標", bie = "别憋瘪別", bin = "彬斌濒滨宾摈賓濱",
    bing = "兵冰柄丙秉饼炳病并餅", bo = "玻菠播拨钵波博勃搏铂箔伯帛泊驳捕駁", bu = "卜哺补埠不布步簿部怖補",
    ca = "擦", cai = "猜裁材才财睬踩采彩菜蔡財", can = "餐参蚕残惭惨灿參殘燦", cang = "苍舱仓沧藏蒼倉",
    cao = "操糙槽曹草", ce = "厕策侧册测測", ceng = "层蹭層", cha = "插叉茬茶查碴搽察岔差诧",
    chai = "拆柴豺", chan = "搀掺蝉馋谗缠铲产阐颤蟬產", chang = "昌猖场尝常长偿肠厂畅唱倡場長腸廠暢",
    chao = "超抄钞朝嘲潮巢吵炒", che = "车扯撤掣彻澈車", chen = "尘臣辰陈晨衬趁塵陳",
    cheng = "撑称城橙成呈乘程惩澄诚承逞骋秤稱誠", chi = "吃痴持匙池迟弛驰齿侈尺赤翅斥炽熾齒遲",
    chong = "充冲虫崇宠蟲寵", chou = "抽酬畴踌稠愁筹仇绸瞅丑臭醜", chu = "初出橱厨躇锄雏除楚础储矗搐触处處觸",
    chuai = "揣", chuan = "川穿椽传船喘串傳", chuang = "疮窗幢床闯创創", chui = "吹炊捶锤垂",
    chun = "春椿纯唇醇蠢純", chuo = "戳绰", ci = "茨磁雌辞慈瓷词此刺赐次詞賜",
    cong = "聪葱囱匆从丛從叢聰", cou = "凑湊", cu = "粗醋簇促", cuan = "蹿篡窜", cui = "摧崔催脆粹淬翠",
    cun = "村存寸", cuo = "磋撮搓措挫错錯",
    da = "搭达答瘩打大達", dai = "呆歹傣戴带殆代贷袋待逮怠帶", dan = "耽担丹单郸掸胆旦氮但惮淡诞弹蛋單彈膽",
    dang = "当挡党荡档當黨", dao = "刀捣蹈倒岛祷导到稻悼道盗島導", de = "德得的", deng = "蹬灯登等瞪凳邓燈",
    di = "堤低滴迪敌笛狄涤翟嫡抵底地蒂第帝弟递缔敵遞", dian = "颠掂滇碘点典靛垫电佃甸店惦奠淀殿點電",
    diao = "叼雕叼掉吊钓调調釣", die = "跌爹碟蝶迭谍叠", ding = "丁盯叮钉顶鼎锭定订頂訂",
    diu = "丢丟", dong = "东冬董懂动栋侗恫冻洞東動凍", dou = "兜抖斗陡豆逗痘鬥",
    du = "都督毒犊独读堵睹赌杜镀肚度渡妒獨讀", duan = "端短锻段断缎斷鍛", dui = "堆兑队对隊對",
    dun = "墩吨蹲敦顿囤钝盾遁頓", duo = "多夺垛躲朵跺舵剁惰堕奪墮",
    e = "蛾峨俄额讹娥恶厄扼遏鄂饿額惡餓", en = "恩", er = "而儿耳尔饵洱二贰兒爾貳",
    fa = "发罚筏伐乏阀法珐發", fan = "藩帆番翻樊矾钒繁凡烦反返范贩犯饭泛飯販", fang = "坊芳方脂肪房防妨仿访纺放訪",
    fei = "菲非啡飞肥匪诽吠肺废沸费飛費廢", fen = "芬酚吩氛分纷坟焚汾粉奋份忿愤粪紛奮",
    feng = "丰封枫蜂峰锋风疯烽逢冯缝讽奉凤風鳳鋒豐", fo = "佛", fou = "否",
    fu = "夫敷肤孵扶拂幅氟符伏俘服浮涪福袱弗甫抚辅俯釜斧脯腑府腐赴副覆赋复傅付阜父腹负富讣附妇缚咐復負",
    ga = "噶嘎", gai = "该改概钙盖溉蓋該", gan = "干甘杆柑竿肝赶感秆敢赣趕", gang = "冈刚钢缸肛纲岗港杠剛鋼",
    gao = "篙皋高膏羔糕搞镐稿告", ge = "哥歌搁戈鸽胳疙割革葛格蛤阁隔铬个各個鴿閣", gei = "给給",
    gen = "根跟", geng = "耕更庚羹埂耿梗", gong = "工攻功恭龚供躬公宫弓巩汞拱贡共宮貢",
    gou = "钩勾沟苟狗垢构购够構購", gu = "辜菇咕箍估沽孤姑鼓古蛊骨谷股故顾固雇顧", gua = "瓜剐寡挂褂掛",
    guai = "乖拐怪", guan = "棺关官冠观管馆罐惯灌贯關觀館慣", guang = "光广逛廣",
    gui = "瑰规圭硅归龟闺轨鬼诡癸桂柜跪贵刽歸龜貴規軌", gun = "辊滚棍滾", guo = "锅郭国果裹过國過",
    ha = "哈", hai = "骸孩海氦亥害骇駭", han = "酣憨邯韩含涵寒函喊罕翰撼捍旱憾悍焊汗汉漢韓",
    hang = "夯杭航", hao = "壕嚎豪毫郝好耗号浩號", he = "呵喝荷菏核禾和何合盒貉阂河涸赫褐鹤贺鶴賀",
    hei = "嘿黑", hen = "痕很狠恨", heng = "哼亨横衡恒橫恆", hong = "轰哄烘虹鸿洪宏弘红紅鴻轟",
    hou = "喉侯猴吼厚候后後", hu = "呼乎忽瑚壶葫胡蝴狐糊湖弧虎唬护互沪户護", hua = "花哗华猾滑画划化话華畫話",
    huai = "槐徊怀淮坏壞懷", huan = "欢环桓还缓换患唤痪焕涣換喚還歡環", huang = "凰皇黄惶煌晃幌恍谎黃",
    hui = "灰挥辉徽恢蛔回毁悔慧卉惠晦贿秽会烩汇讳诲绘會輝毀", hun = "昏婚魂浑混渾", huo = "豁活伙火获或惑霍货祸貨獲",
    ji = "击圾基机畸稽积箕肌饥迹激讥鸡姬绩缉吉极棘辑籍集及急疾汲即嫉级挤几脊己蓟技冀季伎祭剂悸济寄寂计记既忌际妓继纪機擊積雞極集級幾記計繼際",
    jia = "嘉枷夹佳家加荚颊贾甲钾假稼价架驾嫁價", jian = "歼监坚尖笺间煎兼肩艰奸缄茧检柬碱拣捡简俭剪减荐槛鉴践贱见键箭件健舰剑饯渐溅涧建間堅見劍簡減鍵",
    jiang = "僵姜将浆江疆蒋桨奖讲匠酱降將獎講醬", jiao = "蕉椒礁焦胶交郊浇骄娇嚼搅铰矫侥脚狡角饺缴绞剿教酵轿较叫窖覺較教",
    jie = "揭接皆秸街阶截劫节桔杰捷睫竭洁结解姐戒藉芥界借介疥诫届節結階傑", jin = "巾筋斤金今津襟紧锦仅谨进靳晋禁近烬浸尽劲緊進盡僅金",
    jing = "荆兢茎睛晶鲸京惊精粳经井警景颈静境敬镜径痉靖竟竞净經驚靜鏡競鯨", jiong = "炯窘",
    jiu = "揪究纠玖韭久灸九酒厩救旧臼舅咎就疚舊", ju = "鞠拘狙疽居驹菊局咀矩举沮聚拒据巨具距踞锯俱句惧炬剧巨據舉劇",
    juan = "捐娟倦眷卷绢", jue = "撅攫抉掘倔爵觉决诀绝絕決覺", jun = "均菌钧军君峻俊竣郡骏軍駿",
    ka = "喀咖卡咯", kai = "开揩楷凯慨開凱", kan = "刊堪勘坎砍看", kang = "康慷糠扛抗亢炕",
    kao = "考拷烤靠", ke = "坷苛柯棵磕颗科壳咳可渴克刻客课顆殼課", ken = "肯啃垦恳", keng = "坑吭",
    kong = "空恐孔控", kou = "抠口扣寇", ku = "枯哭窟苦酷库裤庫", kua = "夸垮挎跨胯誇",
    kuai = "块筷侩快塊", kuan = "宽款寬", kuang = "匡筐狂框矿眶旷况礦況", kui = "盔岿窥葵奎魁傀馈愧溃",
    kun = "坤昆捆困", kuo = "括扩廓阔擴闊",
    la = "垃拉喇蜡腊辣啦臘", lai = "莱来赖來賴", lan = "蓝婪栏拦篮阑兰澜谰揽览懒缆烂滥藍蘭覽",
    lang = "琅郎狼廊朗浪", lao = "捞劳牢老佬姥酪烙涝勞", le = "勒乐樂", lei = "雷镭蕾磊累儡垒擂肋类泪類",
    leng = "棱楞冷", li = "厘梨犁黎篱狸离漓理李里鲤礼莉荔吏栗丽厉励砾历利痢例俐立粒沥隶力璃哩離鯉禮麗歷厲",
    lia = "俩", lian = "联莲连镰怜涟帘敛脸链恋炼练聯連蓮練鏈臉", liang = "粮凉梁粱良两辆量晾亮谅兩亮糧",
    liao = "撩聊僚疗燎寥辽潦了撂镣廖料療", lie = "列裂烈劣猎獵", lin = "琳林磷霖临邻鳞淋凛赁吝拎臨鱗",
    ling = "玲菱零龄铃伶羚凌灵陵岭领另令靈領齡鈴", liu = "溜琉榴硫馏留刘瘤流柳六劉",
    long = "龙聋咙笼窿隆垄拢隴龍籠", lou = "楼娄搂篓漏陋樓", lu = "芦卢颅庐炉掳卤虏鲁麓碌露路赂鹿潞禄录陆戮盧爐魯陸錄",
    lv = "驴吕铝侣旅履屡缕虑氯律率滤绿綠呂", luan = "峦挛孪滦卵乱亂", lue = "掠略",
    lun = "抡轮伦仑沦纶论輪論", luo = "萝螺罗逻锣箩骡裸落洛骆絡羅螺邏",
    ma = "妈麻玛码蚂马骂嘛吗馬瑪碼", mai = "埋买麦卖迈脉買賣麥邁", man = "瞒蛮满蔓曼慢漫谩滿漫",
    mang = "茫盲氓忙莽", mao = "猫茅锚毛矛铆卯茂冒帽貌贸貓", me = "么",
    mei = "玫枚梅酶霉煤没眉媒镁每美昧寐妹媚沒", men = "门闷们門們", meng = "萌蒙檬盟锰猛梦孟夢",
    mi = "眯醚靡糜迷谜弥米秘觅泌蜜密幂謎覓", mian = "棉眠绵冕免勉娩缅面", miao = "苗描瞄藐秒渺庙妙廟",
    mie = "蔑灭滅", min = "民抿皿敏悯", ming = "明鸣铭名命鳴銘", miu = "谬",
    mo = "摸摹蘑模膜磨摩魔抹末莫墨默沫漠寞陌魔", mou = "谋牟某", mu = "拇牡亩姆母墓暮幕募慕木目睦牧穆",
    na = "拿哪呐钠那娜纳納", nai = "氖乃奶耐奈", nan = "南男难難", nang = "囊", nao = "挠脑恼闹淖腦鬧",
    ne = "呢", nei = "馁内內", nen = "嫩", neng = "能",
    ni = "妮霓倪泥尼拟你匿腻逆溺擬", nian = "蔫拈年碾撵捻念", niang = "娘酿", niao = "鸟尿鳥",
    nie = "捏聂孽啮镊镍涅", nin = "您", ning = "柠狞凝宁拧泞寧", niu = "牛扭钮纽鈕",
    nong = "脓浓农弄濃農", nu = "奴努怒", nv = "女", nuan = "暖", nue = "虐疟", nuo = "挪懦糯诺諾",
    o = "哦", ou = "欧鸥殴藕呕偶沤歐",
    pa = "啪趴爬帕怕琶", pai = "拍排牌徘湃派", pan = "攀潘盘磐盼畔判叛盤", pang = "旁耪胖",
    pao = "抛咆刨炮袍跑泡砲", pei = "胚培裴赔陪配佩沛", pen = "喷盆噴", peng = "砰抨烹澎彭蓬棚硼篷膨朋鹏捧碰鵬",
    pi = "坯砒霹批披劈琵毗啤脾疲皮匹痞僻屁譬", pian = "篇偏片骗騙", piao = "飘漂瓢票飄", pie = "撇瞥",
    pin = "拼频贫品聘頻貧", ping = "乒坪苹萍平凭瓶评屏評", po = "坡泼颇婆破魄迫粕", pou = "剖",
    pu = "扑铺仆莆葡菩蒲埔朴圃普浦谱瀑撲譜",
    qi = "期栖戚妻七凄漆柒沏其棋奇歧畦崎脐齐旗祈祁骑起岂乞企启契砌器气迄弃汽泣讫氣齊騎啟棄",
    qia = "掐恰洽", qian = "牵扦钎铅千迁签仟谦乾黔钱钳前潜遣浅谴堑嵌欠歉錢潛淺",
    qiang = "枪腔强墙蔷抢強牆", qiao = "悄敲锹橇乔侨桥瞧巧翘撬峭俏窍橋喬", qie = "切茄且怯窃",
    qin = "钦侵亲秦琴勤芹擒禽寝沁親", qing = "青轻氢倾卿清擎晴氰情顷请庆輕傾請慶", qiong = "穷琼窮瓊",
    qiu = "秋丘邱球求囚酋", qu = "趋区躯驱屈蛆躯曲取娶龋趣去區驅", quan = "圈颧权醛泉全痊拳犬券劝權勸",
    que = "缺炔瘸却鹊榷确雀卻確", qun = "裙群",
    ran = "然燃冉染", rang = "瓤壤攘嚷让讓", rao = "饶扰绕繞", re = "惹热熱",
    ren = "壬仁人忍韧任认刃妊纫認", reng = "扔仍", ri = "日", rong = "戎茸蓉荣融熔溶容绒冗榮",
    rou = "揉柔肉", ru = "茹蠕儒孺如辱乳汝入褥", ruan = "软軟", rui = "蕊瑞锐銳", run = "闰润潤", ruo = "若弱",
    sa = "撒洒萨薩", sai = "腮鳃塞赛賽", san = "三叁伞散傘", sang = "桑嗓丧喪", sao = "搔骚扫嫂掃",
    se = "瑟色涩", sen = "森", seng = "僧", sha = "莎砂杀刹沙纱傻啥煞殺", shai = "筛晒篩",
    shan = "山删煽衫闪陕擅赡膳善汕扇缮閃善", shang = "伤商赏晌上尚裳傷賞", shao = "梢捎稍烧芍勺韶少哨邵绍燒紹",
    she = "奢赊蛇舌舍赦摄射慑涉社设設攝", shen = "砷申呻伸身深娠绅神沈审婶甚肾慎渗審神",
    sheng = "声生甥牲升绳省盛剩胜圣聲繩勝聖", shi = "师失狮施湿诗尸虱十石拾时什食蚀实识史矢使屎驶始式示士世柿事拭誓逝势是嗜噬适仕侍释饰氏市恃室视试師詩時實識使始視試飾釋",
    shou = "收手首守寿授售受瘦兽獸壽", shu = "蔬枢梳殊抒输叔舒淑疏书赎孰熟薯暑曙署蜀黍鼠属术述树束戍竖墅庶数漱恕書樹屬數術",
    shua = "刷耍", shuai = "摔衰甩帅帥", shuan = "栓拴", shuang = "霜双爽雙", shui = "谁水睡税誰",
    shun = "吮瞬顺舜順", shuo = "说硕朔烁說碩", si = "斯撕嘶思私司丝死肆寺嗣四伺似饲巳絲",
    song = "松耸怂颂送宋讼诵頌", sou = "搜艘擞嗽", su = "苏酥俗素速粟僳塑溯宿诉肃蘇訴",
    suan = "酸蒜算", sui = "虽隋随绥髓碎岁穗遂隧祟雖隨歲", sun = "孙损笋孫損", suo = "蓑梭唆缩琐索锁鎖縮",
    ta = "塌他它她塔獭挞踏", tai = "胎苔抬台泰酞太态汰台態", tan = "坍摊贪瘫滩坛檀痰潭谭谈坦毯袒碳探叹炭譚談",
    tang = "汤塘搪堂棠膛唐糖倘躺淌趟烫湯", tao = "掏涛滔绦萄桃逃淘陶讨套濤討", te = "特",
    teng = "藤腾疼誊騰", ti = "梯剔踢锑提题蹄啼体替嚏涕剃屉體題", tian = "天添填田甜恬舔腆",
    tiao = "挑条迢眺跳條", tie = "贴铁帖鐵", ting = "厅听烃汀廷停亭庭挺艇聽",
    tong = "通桐酮瞳同铜彤童桶捅筒统痛銅統", tou = "偷投头透頭", tu = "凸秃突图徒途涂屠土吐兔圖",
    tuan = "湍团團", tui = "推颓腿蜕褪退", tun = "吞屯臀", tuo = "拖托脱鸵陀驮驼椭妥拓唾脫",
    wa = "哇娃挖洼蛙瓦袜", wai = "歪外", wan = "豌弯湾玩顽丸烷完碗挽晚皖婉宛万腕彎灣萬",
    wang = "汪王亡枉网往旺望忘妄網", wei = "威巍微危韦违桅围唯惟为潍维苇萎委伟伪尾纬未蔚味畏胃喂魏位渭谓慰卫為維衛偉位",
    wen = "瘟温蚊文闻纹吻稳紊问溫聞問穩", weng = "嗡翁瓮", wo = "挝蜗涡窝我斡卧握沃窩臥",
    wu = "巫呜钨乌污诬屋无芜梧吾吴毋武五捂午舞伍侮坞戊雾晤物勿务悟误無務物霧烏",
    xi = "昔熙析西硒矽晰嘻吸锡牺稀息希悉膝夕惜熄烯溪汐犀檄袭席习媳喜铣洗系隙戏细錫習戲細",
    xia = "瞎虾匣霞辖暇峡侠狭下厦夏吓蝦峽狹", xian = "掀锨先仙鲜纤咸贤衔舷闲涎弦嫌显险现献县腺馅羡宪陷限线鮮閒顯現獻線限",
    xiang = "厢镶香箱襄湘乡翔祥详想响享项巷橡像向象鄉詳響項", xiao = "萧硝霄削哮嚣销消宵淆晓小孝校肖啸笑效曉銷",
    xie = "楔些歇蝎鞋协挟携邪斜胁谐写械卸蟹懈泄泻谢屑協寫謝", xin = "薪芯锌欣辛新忻心信衅",
    xing = "星腥猩惺兴刑型形邢行醒幸杏性姓興", xiong = "兄凶胸匈汹雄熊", xiu = "休修羞朽嗅锈秀袖绣",
    xu = "墟需虚须徐许蓄酗叙旭序畜恤絮婿绪续虛須許續", xuan = "轩喧宣悬旋玄选癣眩绚選懸",
    xue = "靴薛学穴雪血學", xun = "勋熏循旬询寻驯巡殉汛训讯逊迅尋訓迅",
    ya = "压押鸦鸭呀丫芽牙蚜崖衙涯雅哑亚讶壓鴉亞", yan = "焉咽阉烟淹盐严研蜒岩延言颜阎炎沿奄掩眼衍演艳堰燕厌砚雁唁彦焰宴谚验煙嚴顏演驗",
    yang = "殃央鸯秧杨扬佯羊洋阳氧仰痒养样漾揚陽養樣", yao = "邀腰妖瑶摇尧遥窑谣姚咬舀药要耀藥",
    ye = "椰噎耶爷野冶也页掖业叶曳腋夜液業葉頁", yi = "一壹医揖铱依伊衣颐夷遗移仪胰疑沂宜姨彝椅蚁倚已乙矣以艺抑易邑屹亿役臆逸肄疫亦裔意毅忆义益溢诣议谊译异翼翌绎醫遺儀藝億議異譯",
    yin = "茵荫因殷音阴姻吟银淫寅饮尹引隐印陰銀飲隱", ying = "英樱婴鹰应缨莹萤营荧蝇迎赢盈影颖硬映鷹應營迎影",
    yo = "哟", yong = "拥佣臃痈庸雍踊蛹咏泳涌永恿勇用擁詠", you = "幽优悠忧尤由邮铀犹油游酉有友右佑釉诱又幼優遊",
    yu = "迂淤于盂榆虞愚舆余俞逾鱼愉渝渔隅予娱雨与屿禹宇语羽玉域芋郁吁遇喻峪御愈欲狱育誉浴寓裕预豫驭魚語與禦預譽",
    yuan = "鸳渊冤元垣袁原援辕园员圆猿源缘远苑愿怨院園圓遠願", yue = "曰约越跃钥岳粤月悦阅約躍悅",
    yun = "耘云郧匀陨允运蕴酝晕韵孕雲運韻",
    za = "匝砸杂雜", zai = "栽哉灾宰载再在咱災載", zan = "攒暂赞贊暫", zang = "赃脏葬藏",
    zao = "遭糟凿藻枣早澡蚤躁噪造皂灶燥", ze = "责择则泽贼責擇澤賊", zei = "贼", zen = "怎", zeng = "增憎曾赠贈",
    zha = "扎喳渣札轧铡闸眨栅榨咋诈炸詐", zhai = "摘斋宅窄债寨債", zhan = "瞻毡詹粘沾盏斩辗崭展蘸栈占战站湛绽戰站",
    zhang = "樟章彰漳张掌涨杖丈帐账仗胀瘴障張漲帳", zhao = "招昭找沼赵照罩兆肇召趙",
    zhe = "遮折哲蛰辙者锗蔗这浙這", zhen = "珍斟真甄砧臻贞针侦枕疹诊震振镇阵陣鎮",
    zheng = "蒸挣睁征狰争怔整拯正政帧症郑证爭證", zhi = "芝枝支吱蜘知肢脂汁之织职直植殖执值侄址指止趾只旨纸志挚掷至致置帜峙制智秩稚质炙痔滞治窒職執質製",
    zhong = "中盅忠钟衷终种肿重仲众鐘終種眾", zhou = "舟周州洲诌粥轴肘帚咒皱宙昼骤晝",
    zhu = "珠株蛛朱猪诸诛逐竹烛煮拄瞩嘱主著柱助蛀贮铸筑住注祝驻豬諸築", zhua = "抓爪", zhuai = "拽",
    zhuan = "专砖转撰赚篆專轉", zhuang = "桩庄装妆撞壮状裝壯狀", zhui = "椎锥追赘坠缀追",
    zhun = "准準", zhuo = "捉拙卓桌琢茁酌啄着灼浊", zi = "兹资姿滋淄孜紫仔籽滓子自渍字資",
    zong = "鬃棕踪宗综总纵總縱", zou = "邹走奏揍", zu = "租足卒族祖诅阻组組", zuan = "钻纂鑽",
    zui = "嘴醉最罪", zun = "尊遵", zuo = "昨左佐柞做作坐座",
}

local PINYIN_FULL = {}
local PINYIN_INIT = {}
for syllable, chars in pairs(PINYIN_SYLLABLE_GROUPS) do
    local initChar = sub(syllable, 1, 1)
    local i = 1
    local len = #chars
    while i <= len do
        local b = byte(chars, i)
        local cLen = (b < 0x80 and 1) or (b < 0xE0 and 2) or (b < 0xF0 and 3) or 4
        local ch = sub(chars, i, i + cLen - 1)
        if not PINYIN_FULL[ch] then
            PINYIN_FULL[ch] = syllable
            PINYIN_INIT[ch] = initChar
        end
        i = i + cLen
    end
end

-- Pooled parsed query state (rebuilt only when query string changes -> 0 GC on list scans)
local lastQueryRaw = nil
local parsedTokenCount = 0
local parsedTokens = {}

-- Reusable DP buffers for full/initial/mixed pinyin matching (max token length 32)
local MAX_DP_LEN = 32
local dpStart = {}
local dpFullHits = {}
for k = 0, MAX_DP_LEN do
    dpStart[k] = -1
    dpFullHits[k] = 0
end

local function ParseTokenIntoPool(slot, tokenStr)
    local tok = parsedTokens[slot]
    if not tok then
        tok = { chars = {} }
        parsedTokens[slot] = tok
    end
    tok.raw = tokenStr
    local chars = tok.chars
    local count = 0
    local i = 1
    local len = #tokenStr
    local isAscii = true
    while i <= len do
        local b = byte(tokenStr, i)
        local cLen = (b < 0x80 and 1) or (b < 0xE0 and 2) or (b < 0xF0 and 3) or 4
        if cLen > 1 or not ((b >= 97 and b <= 122) or (b >= 48 and b <= 57)) then
            isAscii = false
        end
        count = count + 1
        chars[count] = sub(tokenStr, i, i + cLen - 1)
        i = i + cLen
    end
    tok.charCount = count
    tok.isAsciiLetters = isAscii
end

local function PrepareQuery(query)
    if not query or query == "" then
        lastQueryRaw = ""
        parsedTokenCount = 0
        return 0
    end
    if query == lastQueryRaw then
        return parsedTokenCount
    end
    lastQueryRaw = query
    local normalized = strlower(strtrim(query))
    if normalized == "" then
        parsedTokenCount = 0
        return 0
    end
    local tCount = 0
    for word in gmatch(normalized, "%S+") do
        tCount = tCount + 1
        ParseTokenIntoPool(tCount, word)
    end
    parsedTokenCount = tCount
    return tCount
end

-- Zero-GC DP matcher supporting full pinyin ("yiqi"), initials ("yq"), and mixed ("yqi" / "xiaoge")
local function ScorePinyinMatch(textLower, qStr)
    local qLen = #qStr
    if qLen == 0 or qLen > MAX_DP_LEN then return 0 end

    dpStart[0] = 0
    dpFullHits[0] = 0
    for k = 1, qLen do
        dpStart[k] = -1
        dpFullHits[k] = 0
    end

    local charIdx = 0
    local i = 1
    local len = #textLower
    local bestScore = 0

    while i <= len do
        local b = byte(textLower, i)
        local cLen = (b < 0x80 and 1) or (b < 0xE0 and 2) or (b < 0xF0 and 3) or 4
        local ch = sub(textLower, i, i + cLen - 1)
        charIdx = charIdx + 1

        local syl = (cLen > 1) and PINYIN_FULL[ch] or nil
        local init = (cLen == 1) and ch or (syl and PINYIN_INIT[ch])
        if init then
            local sylLen = syl and #syl or 1
            for k = qLen - 1, 0, -1 do
                local st = dpStart[k]
                if st >= 0 then
                    local fullSoFar = dpFullHits[k]
                    local startAt = (k == 0) and charIdx or st

                    -- 1) Try full pinyin syllable match (e.g. "yi", "qi", "xiao", "ge")
                    if syl and sylLen > 1 and k + sylLen <= qLen then
                        if sub(qStr, k + 1, k + sylLen) == syl then
                            local nk = k + sylLen
                            local nf = fullSoFar + 1
                            if dpStart[nk] < 0 or nf > dpFullHits[nk] or (nf == dpFullHits[nk] and startAt > dpStart[nk]) then
                                dpStart[nk] = startAt
                                dpFullHits[nk] = nf
                            end
                        end
                    end

                    -- 2) Try 2-letter consonant cluster (zh/ch/sh) prefix
                    if syl and sylLen > 2 and k + 2 <= qLen and byte(syl, 2) == 104 then -- 'h'
                        if sub(qStr, k + 1, k + 2) == sub(syl, 1, 2) then
                            local nk = k + 2
                            if dpStart[nk] < 0 or fullSoFar > dpFullHits[nk] or (fullSoFar == dpFullHits[nk] and startAt > dpStart[nk]) then
                                dpStart[nk] = startAt
                                dpFullHits[nk] = fullSoFar
                            end
                        end
                    end

                    -- 3) Try single initial / ASCII letter match
                    if sub(qStr, k + 1, k + 1) == init then
                        local nk = k + 1
                        if dpStart[nk] < 0 or fullSoFar > dpFullHits[nk] or (fullSoFar == dpFullHits[nk] and startAt > dpStart[nk]) then
                            dpStart[nk] = startAt
                            dpFullHits[nk] = fullSoFar
                        end
                    end
                end
            end

            if dpStart[qLen] > 0 then
                local span = charIdx - dpStart[qLen] + 1
                local score = 300 + dpFullHits[qLen] * 40 - (span > 150 and 150 or span)
                if dpStart[qLen] == 1 then score = score + 20 end
                if score > bestScore then bestScore = score end
            end
        end
        i = i + cLen
    end

    return bestScore
end

-- Score a single already-lowercased text against one parsed token (0 = no match)
local function ScoreTextForToken(textLower, tok)
    if not textLower or textLower == "" then return 0 end

    -- 1. Fast path: literal substring match
    local pos = find(textLower, tok.raw, 1, true)
    if pos then
        if pos == 1 then
            return 1000
        end
        return 800 - (pos > 200 and 200 or pos)
    end

    local needCount = tok.charCount
    local tokChars = tok.chars

    -- 2. UTF-8 character subsequence match (e.g. "小格" -> "小拉格纳罗斯", "熊猫龙" -> "机械熊猫人幼龙")
    if needCount >= 2 then
        local qIdx = 1
        local firstCharIdx = 0
        local charIdx = 0
        local i = 1
        local len = #textLower
        while i <= len do
            local b = byte(textLower, i)
            local cLen = (b < 0x80 and 1) or (b < 0xE0 and 2) or (b < 0xF0 and 3) or 4
            local ch = sub(textLower, i, i + cLen - 1)
            charIdx = charIdx + 1
            if ch == tokChars[qIdx] then
                if qIdx == 1 then firstCharIdx = charIdx end
                if qIdx == needCount then
                    local span = charIdx - firstCharIdx + 1
                    return 550 - (span > 200 and 200 or span)
                end
                qIdx = qIdx + 1
            end
            i = i + cLen
        end
    end

    -- 3. Pinyin full / initial / mixed match for ASCII queries (e.g. "yq", "yiqi", "yqi", "xmrl")
    if tok.isAsciiLetters then
        return ScorePinyinMatch(textLower, tok.raw)
    end

    return 0
end

function FuzzySearch:Prepare(query)
    local count = PrepareQuery(query)
    return count, parsedTokens
end

function FuzzySearch:ScoreToken(textLower, tok)
    return ScoreTextForToken(textLower, tok)
end

-- Match a single text against query (all space-separated tokens must match).
function FuzzySearch:Match(text, query)
    local tCount = PrepareQuery(query)
    if tCount == 0 then return true, 0 end
    if not text or text == "" then return false, 0 end
    local textLower = strlower(text)
    local totalScore = 0
    for i = 1, tCount do
        local s = ScoreTextForToken(textLower, parsedTokens[i])
        if s <= 0 then return false, 0 end
        totalScore = totalScore + s
    end
    return true, totalScore
end

-- Match across up to 4 text fields (e.g. teamName, targetLabel, groupName, extra).
-- Every token must match at least one field; field order gives slight priority tie-breakers.
function FuzzySearch:MatchFields(query, f1, f2, f3, f4)
    local tCount = PrepareQuery(query)
    if tCount == 0 then return true, 0 end
    local l1 = (f1 and f1 ~= "") and strlower(f1) or nil
    local l2 = (f2 and f2 ~= "") and strlower(f2) or nil
    local l3 = (f3 and f3 ~= "") and strlower(f3) or nil
    local l4 = (f4 and f4 ~= "") and strlower(f4) or nil
    local totalScore = 0
    for i = 1, tCount do
        local tok = parsedTokens[i]
        local best = 0
        if l1 then
            local s = ScoreTextForToken(l1, tok)
            if s > 0 then best = s + 60 end
        end
        if l2 and best < 1000 then
            local s = ScoreTextForToken(l2, tok)
            if s > 0 and (s + 40) > best then best = s + 40 end
        end
        if l3 and best < 1000 then
            local s = ScoreTextForToken(l3, tok)
            if s > 0 and (s + 20) > best then best = s + 20 end
        end
        if l4 and best < 1000 then
            local s = ScoreTextForToken(l4, tok)
            if s > 0 and s > best then best = s end
        end
        if best <= 0 then return false, 0 end
        totalScore = totalScore + best
    end
    return true, totalScore
end
