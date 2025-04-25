/*
AnotherOpportunityTrigger Overview

This trigger was initially created for handling various events on the Opportunity object. It was developed by a prior developer and has since been noted to cause some issues in our org.

IMPORTANT:
- This trigger does not adhere to Salesforce best practices.
- It is essential to review, understand, and refactor this trigger to ensure maintainability, performance, and prevent any inadvertent issues.

ISSUES:
Avoid nested for loop - 1 instance
Avoid DML inside for loop - 1 instance
Bulkify Your Code - 1 instance 
Avoid SOQL Query inside for loop - 2 instances x  
Stop recursion - 1 instance

RESOURCES: 
https://www.salesforceben.com/12-salesforce-apex-best-practices/
https://developer.salesforce.com/blogs/developer-relations/2015/01/apex-best-practices-15-apex-commandments
*/
trigger AnotherOpportunityTrigger on Opportunity (before insert, after insert, before update, after update, before delete, after delete, after undelete) {
    if (Trigger.isBefore){
        if (Trigger.isInsert){
            // Set default Type for new Opportunities
            //Bulkify Code
            for(Opportunity opp : Trigger.new) {
                if (opp.Type == null){
                    opp.Type = 'New Customer';
                }
            }        
        } else if (Trigger.isUpdate){
            // Append Stage changes in Opportunity Description
            //Move up to before update (complete)
            for (Opportunity opp : Trigger.new) {
                Opportunity oldOpp = Trigger.oldMap.get(opp.Id);
    
                if (opp.StageName != null && opp.StageName != oldOpp.StageName) {
                    opp.Description += '\n Stage Change:' + opp.StageName + ':' + DateTime.now().format();
                }
            }
            
        } else if (Trigger.isDelete){
            // Prevent deletion of closed Opportunities
            for (Opportunity oldOpp : Trigger.old){
                if (oldOpp.IsClosed){
                    oldOpp.addError('Cannot delete closed opportunity');
                }
            }
        }
    }

    if (Trigger.isAfter){
        if (Trigger.isInsert){
            // Create a new Task for newly inserted Opportunities
            //DML in For Loop (complete)
            List<Task> tasks = new List<Task>();
            for (Opportunity opp : Trigger.new){
                Task tsk = new Task();
                tsk.Subject = 'Call Primary Contact';
                tsk.WhatId = opp.Id;
                tsk.WhoId = opp.Primary_Contact__c;
                tsk.OwnerId = opp.OwnerId;
                tsk.ActivityDate = Date.today().addDays(3);
                //Add new Task to List
                tasks.add(tsk);   
            }
            if (!tasks.isEmpty()) {
                insert tasks;
            }

        } 
        // Send email notifications when an Opportunity is deleted 
        else if (Trigger.isDelete){
            notifyOwnersOpportunityDeleted(Trigger.old);
        } 
        // Assign the primary contact to undeleted Opportunities
        else if (Trigger.isUndelete){
            assignPrimaryContact(Trigger.newMap);
        }
    }

    /*
    notifyOwnersOpportunityDeleted:
    - Sends an email notification to the owner of the Opportunity when it gets deleted.
    - Uses Salesforce's Messaging.SingleEmailMessage to send the email.
    */
    private static void notifyOwnersOpportunityDeleted(List<Opportunity> opps) {
        List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
        // Get User Ids from Opp - put in set
        Set<Id> userIds = new Set<Id>();
    
        // Loop through Opps, adding users to the set of users to query for
        for (Opportunity opp : opps) {
            userIds.add(opp.OwnerId);
        }
    
        // Query once outside loop
        Map<Id, User> usersMap = new Map<Id, User>(
            [SELECT Id, Email FROM User WHERE Id IN :userIds]
        );
    
        for (Opportunity opp : opps) {
            String[] toAddresses = new String[] {usersMap.get(opp.OwnerId).Email};
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(toAddresses);
            mail.setSubject('Opportunity Deleted : ' + opp.Name);
            mail.setPlainTextBody('Your Opportunity: ' + opp.Name +' has been deleted.');
            mails.add(mail);
        }        
        
        try {
            Messaging.sendEmail(mails);
        } catch (Exception e){
            System.debug('Exception: ' + e.getMessage());
        }
    }

    /*
    assignPrimaryContact:
    - Assigns a primary contact with the title of 'VP Sales' to undeleted Opportunities.
    - Only updates the Opportunities that don't already have a primary contact.
    */
    private static void assignPrimaryContact(Map<Id,Opportunity> oppNewMap) {        
    
        //collection of accountIds
        Set<Id> accountIds = new Set<Id>();
        for (Opportunity opp : oppNewMap.values()){            
            if(opp.AccountId != null) {
                accountIds.add(opp.AccountId);
            }
        }
        //Query Contacts from AccountIds
        List<Contact> primaryContacts = [
                SELECT Id, AccountId 
                FROM Contact 
                WHERE Title = 'VP Sales' AND AccountId IN :accountIds
            ];
        //Build Map AccountId to one VP Sales Contact for easy lookup
        Map<Id, Contact> accountToVPContactMap = new Map<Id, Contact>();
        //Loop Contacts and Assign Values to Map
        for (Contact c : primaryContacts) {
            if (!accountToVPContactMap.containsKey(c.AccountId)) {
                accountToVPContactMap.put(c.AccountId, c);
            }
        }     
        //Collection opp variable for bulk update
        List<Opportunity> oppsToUpdate = new List<Opportunity>();
        //Loop Opps
        for (Opportunity opp :oppNewMap.values()) {
            //Determine if current opp accountId in in the Map
            if (accountToVPContactMap.containsKey(opp.AccountId) && opp.Primary_Contact__c == null) {
                //Single Current - Opp Values to update 
                Opportunity oppToUpdate = new Opportunity(
                    Id = opp.Id,
                    Primary_Contact__c = accountToVPContactMap.get(opp.AccountId).Id
                );
                //add to collection variable for update
                oppsToUpdate.add(oppToUpdate);
            }
        }
        //Perform DML only if needed
        if (!oppsToUpdate.isEmpty()) {
            update oppsToUpdate;
        }
    }
}