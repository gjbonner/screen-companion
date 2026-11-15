/// Phrases the speech recognizer should favor, so marketing and ad-tech terms aren't misheard
/// (for example "color scheme" heard as "color skin", or "ROAS" as "Ross").
///
/// Keep this list to distinctive terms: names, jargon, and multi-word phrases. Everyday single words
/// ("reach", "campaign", "column") bias normal speech toward them and make recognition worse.
public enum SpeechVocabulary {
	public static let phrases: [String] = platforms + metrics + phrasesFromTheWork

	static let platforms = [
		"Shopify",
		"Meta Ads Manager",
		"Ads Manager",
		"Google Ads",
		"TikTok Ads",
		"Klaviyo",
		"Google Analytics",
		"GA4",
		"Triple Whale",
		"Northbeam",
	]

	static let metrics = [
		"ROAS",
		"return on ad spend",
		"CPC",
		"CPM",
		"CPA",
		"CTR",
		"click-through rate",
		"CAC",
		"LTV",
		"AOV",
		"conversion rate",
		"attribution window",
	]

	static let phrasesFromTheWork = [
		"ad set",
		"ad group",
		"ad creative",
		"lookalike audience",
		"daily budget",
		"lifetime budget",
		"bid strategy",
		"cost cap",
		"Advantage+",
		"Performance Max",
		"Conversions API",
		"landing page",
		"color scheme",
	]
}
