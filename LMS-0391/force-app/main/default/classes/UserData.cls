public without sharing class UserData {

	public static User getCurrentUserData() {
		Id userId = UserInfo.getUserId();
		List<User> users = [
			SELECT Id, Name, Email, ManagerId, Manager.Email FROM USER WHERE ID =: userId
		];
		return users[0];
	}
}