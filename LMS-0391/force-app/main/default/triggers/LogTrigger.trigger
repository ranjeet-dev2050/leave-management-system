trigger LogTrigger on Log__e (after insert) {
	Logger.handleLogEvents(Trigger.new);
}