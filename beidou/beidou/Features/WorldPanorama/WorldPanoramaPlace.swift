//
//  WorldPanoramaPlace.swift
//  beidou
//  Author: Liuzheng <bryant_liu24@126.com>
//
//  国内热门景区全景入口数据。
//

import Foundation

struct WorldPanoramaPlace {
    let name: String
    let region: String
    let province: String
    let city: String
    let country: String
    let summary: String
    let imageURL: URL
    let imageName: String

    var searchText: String {
        "\(name) \(region) \(province) \(city) \(country) \(summary)".lowercased()
    }

    var localizedRegion: String {
        switch region {
        case "热门": return L10n.t("world.category.popular")
        case "华北": return L10n.t("world.category.north")
        case "华东": return L10n.t("world.category.east")
        case "华中": return L10n.t("world.category.central")
        case "华南": return L10n.t("world.category.south")
        case "西南": return L10n.t("world.category.southwest")
        case "西北": return L10n.t("world.category.northwest")
        case "东北": return L10n.t("world.category.northeast")
        default: return region
        }
    }

    var localizedCountry: String {
        let area = province == city ? city : "\(province) · \(city)"
        return "\(localizedRegion) · \(area)"
    }

    var localizedSummary: String {
        L10n.t("world.scenic_summary")
    }

    static let categories = ["热门", "华北", "华东", "华中", "华南", "西南", "西北", "东北"]

    static let thumbnailURL = URL(string: "http://dimg02.c-ctrip.com/images/tg/726/539/317/8e9d61e440264196833846d115c43dc8_C_186_105.jpg")!

    static var all: [WorldPanoramaPlace] {
        north + east + central + south + southwest + northwest + northeast
    }

    static func places(in category: String) -> [WorldPanoramaPlace] {
        switch category {
        case "热门": return popular
        case "华北": return north
        case "华东": return east
        case "华中": return central
        case "华南": return south
        case "西南": return southwest
        case "西北": return northwest
        case "东北": return northeast
        default: return popular
        }
    }

    private static var popular: [WorldPanoramaPlace] {
        Array((north + east + central + south + southwest + northwest + northeast).prefix(50)).enumerated().map { index, place in
            WorldPanoramaPlace(
                name: place.name,
                region: "热门",
                province: place.province,
                city: place.city,
                country: place.country,
                summary: place.summary,
                imageURL: place.imageURL,
                imageName: coverName(for: index, region: "热门")
            )
        }
    }

    private static var north: [WorldPanoramaPlace] {
        make(region: "华北", names: [
            "故宫博物院", "八达岭长城", "颐和园", "天坛公园", "圆明园遗址公园", "恭王府", "明十三陵", "慕田峪长城", "北京奥林匹克公园", "北海公园",
            "承德避暑山庄", "山海关景区", "白洋淀景区", "清东陵", "清西陵", "野三坡百里峡", "西柏坡纪念馆", "娲皇宫景区", "广府古城", "赵州桥景区",
            "平遥古城", "云冈石窟", "五台山风景名胜区", "晋祠博物馆", "乔家大院", "皇城相府", "雁门关景区", "壶口瀑布山西景区", "悬空寺", "绵山风景区",
            "响沙湾旅游景区", "成吉思汗陵旅游区", "阿尔山国家森林公园", "呼伦贝尔大草原", "满洲里中俄边境旅游区", "额济纳胡杨林景区", "希拉穆仁草原", "乌兰布统草原", "昭君博物院", "大召寺",
            "天津古文化街", "天津盘山风景名胜区", "天津之眼", "意大利风情区", "瓷房子", "五大道文化旅游区", "黄崖关长城", "航母主题公园", "海河风景线", "国家海洋博物馆"
        ])
    }

    private static var east: [WorldPanoramaPlace] {
        make(region: "华东", names: [
            "上海外滩", "东方明珠广播电视塔", "豫园", "上海迪士尼度假区", "朱家角古镇", "南京路步行街", "上海野生动物园", "上海科技馆", "上海中心大厦", "田子坊",
            "苏州园林", "南京夫子庙秦淮风光带", "中山陵景区", "无锡鼋头渚", "灵山胜境", "周庄古镇", "同里古镇", "扬州瘦西湖", "镇江金山寺", "连云港花果山",
            "杭州西湖风景名胜区", "乌镇景区", "西塘古镇", "普陀山风景名胜区", "千岛湖风景区", "雁荡山风景名胜区", "横店影视城", "天台山景区", "南浔古镇", "溪口雪窦山景区",
            "黄山风景区", "宏村景区", "西递景区", "九华山风景区", "天柱山风景区", "三河古镇", "天堂寨景区", "徽州古城", "齐云山风景区", "琅琊山风景区",
            "泰山风景名胜区", "曲阜三孔景区", "青岛崂山风景区", "蓬莱阁景区", "刘公岛景区", "台儿庄古城", "趵突泉景区", "大明湖景区", "沂蒙山旅游区", "威海华夏城"
        ])
    }

    private static var central: [WorldPanoramaPlace] {
        make(region: "华中", names: [
            "武汉黄鹤楼公园", "东湖生态旅游风景区", "武当山风景区", "神农架生态旅游区", "三峡大坝旅游区", "恩施大峡谷", "古隆中景区", "荆州古城", "清江画廊", "木兰文化生态旅游区",
            "嵩山少林景区", "洛阳龙门石窟", "云台山风景名胜区", "清明上河园", "殷墟景区", "老君山风景区", "白云山风景区", "鸡公山风景区", "开封府景区", "芒砀山旅游区",
            "张家界武陵源风景名胜区", "岳阳楼君山岛景区", "衡山风景名胜区", "凤凰古城", "韶山旅游区", "岳麓山橘子洲旅游区", "崀山风景名胜区", "桃花源景区", "东江湖旅游区", "天门山国家森林公园",
            "庐山风景名胜区", "三清山风景名胜区", "婺源江湾景区", "井冈山风景名胜区", "滕王阁旅游区", "龙虎山风景名胜区", "景德镇古窑民俗博览区", "明月山旅游区", "龟峰风景名胜区", "瑞金共和国摇篮景区",
            "神农山风景区", "伏牛山老界岭", "白马寺", "尧山风景区", "南湾湖风景区", "嵖岈山风景区", "红旗渠风景区", "太行大峡谷", "炎帝陵景区", "洞庭湖旅游区"
        ])
    }

    private static var south: [WorldPanoramaPlace] {
        make(region: "华南", names: [
            "广州长隆旅游度假区", "深圳华侨城旅游度假区", "世界之窗", "锦绣中华民俗村", "丹霞山风景名胜区", "开平碉楼文化旅游区", "罗浮山风景区", "白云山风景区", "连州地下河", "雁南飞茶田景区",
            "惠州西湖", "南澳岛生态旅游区", "珠海长隆海洋王国", "巽寮湾旅游区", "孙中山故里旅游区", "西樵山风景名胜区", "鼎湖山风景区", "七星岩景区", "海陵岛大角湾", "湖光岩风景区",
            "桂林漓江风景区", "阳朔西街", "象鼻山景区", "龙脊梯田景区", "德天跨国瀑布景区", "北海银滩旅游区", "涠洲岛景区", "青秀山风景区", "黄姚古镇", "通灵大峡谷",
            "三亚南山文化旅游区", "蜈支洲岛旅游区", "天涯海角游览区", "呀诺达雨林文化旅游区", "分界洲岛旅游区", "大小洞天旅游区", "亚龙湾热带天堂森林公园", "槟榔谷黎苗文化旅游区", "海口骑楼老街", "火山口地质公园",
            "鼓浪屿风景名胜区", "武夷山风景名胜区", "福建土楼永定景区", "福建土楼南靖景区", "太姥山风景区", "清源山风景区", "三坊七巷", "湄洲岛妈祖文化旅游区", "东山岛风景区", "白水洋鸳鸯溪景区"
        ])
    }

    private static var southwest: [WorldPanoramaPlace] {
        make(region: "西南", names: [
            "都江堰景区", "青城山景区", "峨眉山风景区", "乐山大佛景区", "九寨沟风景名胜区", "黄龙风景名胜区", "稻城亚丁景区", "阆中古城", "剑门关景区", "海螺沟景区",
            "重庆武隆喀斯特旅游区", "大足石刻景区", "巫山小三峡", "酉阳桃花源景区", "金佛山风景区", "黑山谷景区", "洪崖洞民俗风貌区", "磁器口古镇", "白帝城瞿塘峡景区", "仙女山国家森林公园",
            "丽江古城", "玉龙雪山景区", "石林风景区", "大理古城", "崇圣寺三塔", "泸沽湖景区", "西双版纳热带植物园", "普达措国家公园", "腾冲火山热海景区", "元阳哈尼梯田",
            "黄果树瀑布景区", "梵净山景区", "荔波小七孔景区", "西江千户苗寨", "镇远古城", "赤水丹霞旅游区", "织金洞景区", "龙宫风景名胜区", "百里杜鹃景区", "青岩古镇",
            "布达拉宫", "大昭寺", "纳木错景区", "羊卓雍措", "雅鲁藏布大峡谷", "巴松措景区", "珠峰大本营", "扎什伦布寺", "色拉寺", "罗布林卡"
        ])
    }

    private static var northwest: [WorldPanoramaPlace] {
        make(region: "西北", names: [
            "秦始皇帝陵博物院", "华山风景名胜区", "大唐芙蓉园", "西安城墙", "大雁塔景区", "陕西历史博物馆", "法门寺文化景区", "黄帝陵景区", "壶口瀑布陕西景区", "太白山国家森林公园",
            "嘉峪关关城", "敦煌莫高窟", "鸣沙山月牙泉", "张掖七彩丹霞", "麦积山石窟", "崆峒山风景区", "拉卜楞寺", "官鹅沟景区", "扎尕那景区", "玉门关遗址",
            "青海湖景区", "塔尔寺", "茶卡盐湖", "祁连卓尔山", "门源百里油菜花海", "互助土族故土园", "坎布拉国家森林公园", "可可西里自然保护区", "察尔汗盐湖", "贵德国家地质公园",
            "天山天池风景区", "喀纳斯景区", "赛里木湖景区", "那拉提旅游风景区", "巴音布鲁克景区", "可可托海景区", "火焰山景区", "葡萄沟景区", "喀什古城", "帕米尔旅游区",
            "沙坡头旅游景区", "镇北堡西部影城", "西夏陵国家考古遗址公园", "水洞沟旅游区", "贺兰山岩画", "鸣翠湖国家湿地公园", "六盘山国家森林公园", "沙湖旅游区", "须弥山石窟", "黄河楼景区"
        ])
    }

    private static var northeast: [WorldPanoramaPlace] {
        make(region: "东北", names: [
            "长白山景区", "净月潭国家森林公园", "伪满皇宫博物院", "查干湖景区", "高句丽文物古迹旅游景区", "松花湖风景名胜区", "向海自然保护区", "六鼎山文化旅游区", "长影世纪城", "北大湖滑雪度假区",
            "沈阳故宫博物院", "大连老虎滩海洋公园", "金石滩国家旅游度假区", "本溪水洞景区", "千山风景名胜区", "盘锦红海滩景区", "鸭绿江断桥景区", "兴城古城", "医巫闾山风景区", "凤凰山景区",
            "哈尔滨太阳岛风景区", "五大连池风景区", "镜泊湖风景名胜区", "漠河北极村旅游区", "扎龙自然保护区", "亚布力滑雪旅游度假区", "中央大街", "圣索菲亚教堂", "虎林珍宝岛", "汤旺河林海奇石景区",
            "雪乡国家森林公园", "伊春五营国家森林公园", "兴凯湖旅游区", "北极圣诞村", "哈尔滨极地公园", "龙塔", "凤凰山国家森林公园", "大庆铁人王进喜纪念馆", "黑瞎子岛旅游区", "呼兰河口湿地公园",
            "关东影视城", "沈阳棋盘山风景区", "抚顺赫图阿拉城", "丹东凤凰山", "旅顺口风景名胜区", "营口鲅鱼圈山海广场", "葫芦岛龙湾海滨", "朝阳鸟化石国家地质公园", "阜新海棠山", "辽阳广佑寺"
        ])
    }

    private static func make(region: String, names: [String]) -> [WorldPanoramaPlace] {
        names.enumerated().map { index, name in
            let area = administrativeArea(region: region, index: index)
            return WorldPanoramaPlace(
                name: name,
                region: region,
                province: area.province,
                city: area.city,
                country: area.province == area.city ? area.city : "\(area.province) · \(area.city)",
                summary: L10n.t("world.scenic_summary"),
                imageURL: thumbnailURL,
                imageName: coverName(for: index, region: region)
            )
        }
    }

    private static func administrativeArea(region: String, index: Int) -> (province: String, city: String) {
        let cities: [String]
        let province: String

        switch region {
        case "华北":
            cities = [
                "北京市", "北京市", "北京市", "北京市", "北京市", "北京市", "北京市", "北京市", "北京市", "北京市",
                "承德市", "秦皇岛市", "保定市", "唐山市", "保定市", "保定市", "石家庄市", "邯郸市", "邯郸市", "石家庄市",
                "晋中市", "大同市", "忻州市", "太原市", "晋中市", "晋城市", "忻州市", "临汾市", "大同市", "晋中市",
                "鄂尔多斯市", "鄂尔多斯市", "兴安盟", "呼伦贝尔市", "呼伦贝尔市", "阿拉善盟", "包头市", "赤峰市", "呼和浩特市", "呼和浩特市",
                "天津市", "天津市", "天津市", "天津市", "天津市", "天津市", "天津市", "天津市", "天津市", "天津市"
            ]
            switch index {
            case 0..<10: province = "北京市"
            case 10..<20: province = "河北省"
            case 20..<30: province = "山西省"
            case 30..<40: province = "内蒙古自治区"
            default: province = "天津市"
            }
        case "华东":
            cities = [
                "上海市", "上海市", "上海市", "上海市", "上海市", "上海市", "上海市", "上海市", "上海市", "上海市",
                "苏州市", "南京市", "南京市", "无锡市", "无锡市", "苏州市", "苏州市", "扬州市", "镇江市", "连云港市",
                "杭州市", "嘉兴市", "嘉兴市", "舟山市", "杭州市", "温州市", "金华市", "台州市", "湖州市", "宁波市",
                "黄山市", "黄山市", "黄山市", "池州市", "安庆市", "合肥市", "六安市", "黄山市", "黄山市", "滁州市",
                "泰安市", "济宁市", "青岛市", "烟台市", "威海市", "枣庄市", "济南市", "济南市", "临沂市", "威海市"
            ]
            switch index {
            case 0..<10: province = "上海市"
            case 10..<20: province = "江苏省"
            case 20..<30: province = "浙江省"
            case 30..<40: province = "安徽省"
            default: province = "山东省"
            }
        case "华中":
            cities = [
                "武汉市", "武汉市", "十堰市", "神农架林区", "宜昌市", "恩施土家族苗族自治州", "襄阳市", "荆州市", "宜昌市", "武汉市",
                "郑州市", "洛阳市", "焦作市", "开封市", "安阳市", "洛阳市", "洛阳市", "信阳市", "开封市", "商丘市",
                "张家界市", "岳阳市", "衡阳市", "湘西土家族苗族自治州", "湘潭市", "长沙市", "邵阳市", "常德市", "郴州市", "张家界市",
                "九江市", "上饶市", "上饶市", "吉安市", "南昌市", "鹰潭市", "景德镇市", "宜春市", "上饶市", "赣州市",
                "焦作市", "南阳市", "洛阳市", "平顶山市", "信阳市", "驻马店市", "安阳市", "安阳市", "株洲市", "岳阳市"
            ]
            switch index {
            case 0..<10: province = "湖北省"
            case 10..<20, 40..<48: province = "河南省"
            case 20..<30, 48..<50: province = "湖南省"
            default: province = "江西省"
            }
        case "华南":
            cities = [
                "广州市", "深圳市", "深圳市", "深圳市", "韶关市", "江门市", "惠州市", "广州市", "清远市", "梅州市",
                "惠州市", "汕头市", "珠海市", "惠州市", "中山市", "佛山市", "肇庆市", "肇庆市", "阳江市", "湛江市",
                "桂林市", "桂林市", "桂林市", "桂林市", "崇左市", "北海市", "北海市", "南宁市", "贺州市", "百色市",
                "三亚市", "三亚市", "三亚市", "保亭黎族苗族自治县", "陵水黎族自治县", "三亚市", "三亚市", "保亭黎族苗族自治县", "海口市", "海口市",
                "厦门市", "南平市", "龙岩市", "漳州市", "宁德市", "泉州市", "福州市", "莆田市", "漳州市", "宁德市"
            ]
            switch index {
            case 0..<20: province = "广东省"
            case 20..<30: province = "广西壮族自治区"
            case 30..<40: province = "海南省"
            default: province = "福建省"
            }
        case "西南":
            cities = [
                "成都市", "成都市", "乐山市", "乐山市", "阿坝藏族羌族自治州", "阿坝藏族羌族自治州", "甘孜藏族自治州", "南充市", "广元市", "甘孜藏族自治州",
                "重庆市", "重庆市", "重庆市", "重庆市", "重庆市", "重庆市", "重庆市", "重庆市", "重庆市", "重庆市",
                "丽江市", "丽江市", "昆明市", "大理白族自治州", "大理白族自治州", "丽江市", "西双版纳傣族自治州", "迪庆藏族自治州", "保山市", "红河哈尼族彝族自治州",
                "安顺市", "铜仁市", "黔南布依族苗族自治州", "黔东南苗族侗族自治州", "黔东南苗族侗族自治州", "遵义市", "毕节市", "安顺市", "毕节市", "贵阳市",
                "拉萨市", "拉萨市", "拉萨市", "山南市", "林芝市", "林芝市", "日喀则市", "日喀则市", "拉萨市", "拉萨市"
            ]
            switch index {
            case 0..<10: province = "四川省"
            case 10..<20: province = "重庆市"
            case 20..<30: province = "云南省"
            case 30..<40: province = "贵州省"
            default: province = "西藏自治区"
            }
        case "西北":
            cities = [
                "西安市", "渭南市", "西安市", "西安市", "西安市", "西安市", "宝鸡市", "延安市", "延安市", "宝鸡市",
                "嘉峪关市", "酒泉市", "酒泉市", "张掖市", "天水市", "平凉市", "甘南藏族自治州", "陇南市", "甘南藏族自治州", "酒泉市",
                "海南藏族自治州", "西宁市", "海西蒙古族藏族自治州", "海北藏族自治州", "海北藏族自治州", "海东市", "黄南藏族自治州", "玉树藏族自治州", "海西蒙古族藏族自治州", "海南藏族自治州",
                "昌吉回族自治州", "阿勒泰地区", "博尔塔拉蒙古自治州", "伊犁哈萨克自治州", "巴音郭楞蒙古自治州", "阿勒泰地区", "吐鲁番市", "吐鲁番市", "喀什地区", "喀什地区",
                "中卫市", "银川市", "银川市", "银川市", "银川市", "银川市", "固原市", "石嘴山市", "固原市", "吴忠市"
            ]
            switch index {
            case 0..<10: province = "陕西省"
            case 10..<20: province = "甘肃省"
            case 20..<30: province = "青海省"
            case 30..<40: province = "新疆维吾尔自治区"
            default: province = "宁夏回族自治区"
            }
        case "东北":
            cities = [
                "延边朝鲜族自治州", "长春市", "长春市", "松原市", "通化市", "吉林市", "白城市", "延边朝鲜族自治州", "长春市", "吉林市",
                "沈阳市", "大连市", "大连市", "本溪市", "鞍山市", "盘锦市", "丹东市", "葫芦岛市", "锦州市", "丹东市",
                "哈尔滨市", "黑河市", "牡丹江市", "大兴安岭地区", "齐齐哈尔市", "哈尔滨市", "哈尔滨市", "哈尔滨市", "鸡西市", "伊春市",
                "牡丹江市", "伊春市", "鸡西市", "大兴安岭地区", "哈尔滨市", "哈尔滨市", "哈尔滨市", "大庆市", "佳木斯市", "哈尔滨市",
                "沈阳市", "沈阳市", "抚顺市", "丹东市", "大连市", "营口市", "葫芦岛市", "朝阳市", "阜新市", "辽阳市"
            ]
            switch index {
            case 0..<10: province = "吉林省"
            case 10..<20, 40..<50: province = "辽宁省"
            default: province = "黑龙江省"
            }
        default:
            return (region, region)
        }

        guard cities.indices.contains(index) else { return (province, province) }
        return (province, cities[index])
    }

    private static func coverName(for index: Int, region: String) -> String {
        let regionOffset: Int
        switch region {
        case "热门": regionOffset = 17
        case "华北": regionOffset = 0
        case "华东": regionOffset = 4
        case "华中": regionOffset = 8
        case "华南": regionOffset = 12
        case "西南": regionOffset = 16
        case "西北": regionOffset = 20
        case "东北": regionOffset = 6
        default: regionOffset = 0
        }
        return String(format: "ScenicCover%02d", ((index + regionOffset) % 24) + 1)
    }
}

struct WorldPanoramaCoordinate: Codable {
    let latitude: Double
    let longitude: Double
}

enum WorldPanoramaCoordinateCache {
    private static let storageKey = "world_panorama_baidu_coordinates_v1"

    static func coordinate(for place: WorldPanoramaPlace) -> WorldPanoramaCoordinate? {
        coordinates()[cacheKey(for: place)]
    }

    static func save(
        latitude: Double,
        longitude: Double,
        for place: WorldPanoramaPlace
    ) {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return }
        var values = coordinates()
        values[cacheKey(for: place)] = WorldPanoramaCoordinate(
            latitude: latitude,
            longitude: longitude
        )
        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func coordinates() -> [String: WorldPanoramaCoordinate] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let values = try? JSONDecoder().decode([String: WorldPanoramaCoordinate].self, from: data) else {
            return [:]
        }
        return values
    }

    private static func cacheKey(for place: WorldPanoramaPlace) -> String {
        "\(place.province)|\(place.city)|\(place.name)"
    }
}
