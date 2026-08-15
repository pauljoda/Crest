import SwiftUI

extension Binding where Value == BrowserSpaceBranding {
    var editorThemeMode: Binding<BrowserSpaceThemeMode> {
        Binding<BrowserSpaceThemeMode>(
            get: { wrappedValue.themeMode },
            set: { newValue in
                editorUpdate { $0.themeMode = newValue }
            }
        )
    }

    var editorGradientAngle: Binding<Double> {
        Binding<Double>(
            get: { wrappedValue.gradientAngle },
            set: { newValue in
                editorUpdate { $0.gradientAngle = newValue }
            }
        )
    }

    var editorShowsTexture: Binding<Bool> {
        Binding<Bool>(
            get: { wrappedValue.showsTexture },
            set: { newValue in
                editorUpdate { $0.showsTexture = newValue }
            }
        )
    }

    var editorBannerStrength: Binding<Double> {
        Binding<Double>(
            get: { wrappedValue.bannerStrength },
            set: { newValue in
                editorUpdate { $0.bannerStrength = newValue }
            }
        )
    }

    var editorReadabilityFade: Binding<Double> {
        Binding<Double>(
            get: { wrappedValue.readabilityFade },
            set: { newValue in
                editorUpdate { $0.readabilityFade = newValue }
            }
        )
    }

    var editorIconStyle: Binding<BrowserSpaceIconStyle> {
        Binding<BrowserSpaceIconStyle>(
            get: { wrappedValue.iconStyle },
            set: { newValue in
                editorUpdate { $0.iconStyle = newValue }
            }
        )
    }
}
