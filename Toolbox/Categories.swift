import SwiftUI

/// Preset categories. Generic names only, SF Symbols only, no third-party
/// artwork or brand assets.
enum AppCategories {
    static let expense: [String] = [
        "餐饮", "购物", "日用", "交通",
        "蔬菜", "水果", "零食", "运动",
        "娱乐", "通讯", "服饰", "美容",
        "住房", "居家", "孩子", "长辈",
        "社交", "旅行", "烟酒", "数码",
        "汽车", "医疗", "书籍", "学习",
        "宠物", "礼金", "礼物", "办公",
        "维修", "捐赠", "彩票", "亲友",
        "快递", "其他",
    ]

    static let income: [String] = [
        "工资", "兼职", "理财", "奖金", "其他",
    ]

    static func icon(for category: String) -> String {
        switch category {
        case "餐饮": return "fork.knife"
        case "购物": return "bag.fill"
        case "日用": return "basket.fill"
        case "交通": return "car.fill"
        case "蔬菜": return "carrot.fill"
        case "水果": return "applelogo"
        case "零食": return "cup.and.saucer.fill"
        case "运动": return "figure.run"
        case "娱乐": return "gamecontroller.fill"
        case "通讯": return "phone.fill"
        case "服饰": return "tshirt.fill"
        case "美容": return "sparkles"
        case "住房": return "house.fill"
        case "居家": return "sofa.fill"
        case "孩子": return "face.smiling.fill"
        case "长辈": return "person.fill"
        case "社交": return "person.2.fill"
        case "旅行": return "airplane"
        case "烟酒": return "wineglass.fill"
        case "数码": return "iphone"
        case "汽车": return "steeringwheel"
        case "医疗": return "cross.fill"
        case "书籍": return "book.fill"
        case "学习": return "graduationcap.fill"
        case "宠物": return "pawprint.fill"
        case "礼金": return "gift.fill"
        case "礼物": return "gift.circle.fill"
        case "办公": return "briefcase.fill"
        case "维修": return "wrench.fill"
        case "捐赠": return "heart.fill"
        case "彩票": return "ticket.fill"
        case "亲友": return "person.3.fill"
        case "快递": return "shippingbox.fill"
        case "工资": return "banknote.fill"
        case "兼职": return "briefcase.fill"
        case "理财": return "chart.line.uptrend.xyaxis"
        case "奖金": return "gift.fill"
        default: return "ellipsis.circle.fill"
        }
    }
}
