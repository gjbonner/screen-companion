import SwiftUI

struct ContentView: View {
	var body: some View {
		VStack(spacing: 12) {
			Image(systemName: "rectangle.on.rectangle")
				.imageScale(.large)
				.foregroundStyle(.tint)
			Text("ScreenCompanion")
				.font(.title)
		}
		.padding()
		.frame(minWidth: 400, minHeight: 300)
	}
}

#Preview {
	ContentView()
}
