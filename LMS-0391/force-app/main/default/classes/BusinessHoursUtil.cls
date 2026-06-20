public without sharing class BusinessHoursUtil {

	public static final String DEFAULT_BH_NAME = 'Org Default Hours';

	public static List<BusinessHours> getDefaultBusinessHour() {
		String businessHourName = DEFAULT_BH_NAME;
		List<BusinessHours> businessHours = [
			SELECT Id, Name, IsActive FROM BusinessHours WHERE Name =: businessHourName AND IsActive = true
		];
		return businessHours;
	}
}