var USERINPUT = USERINPUT || {};


function show_apprise($form, message) {
	/*we no longer allow user to igore IRU validation errors
	apprise(message, {
		    'confirm': false, 		// Ok and Cancel buttons
		    'verify': true, 	// Yes and No buttons
		    'input': false, 		// Text input (can be true or string for default text)
		    'animate': true, 	// Groovy animation (can true or number, default is 400)
		    'textOk': 'Ok', 	// Ok button default text
		    'textCancel': 'Cancel', // Cancel button default text
		    'textYes': 'Ignore Errors', 	// Yes button default text
		    'textNo': 'Fix Errors', 	// No button default text
		    'position': 'center'// position center (y-axis) any other option will default to 100 top
		}, function (r) {
				if (r) {$form.unbind("submit");$form.submit();}
			}
	);
	*/
	apprise(message);
}

function call_validation_api($form, $div, postData, accountId) {
	var myData = JSON.stringify(postData["userInput"]);
	console.log("iru_validation.call_validation_api() myData=", myData);
	
	var url = "/rundb/api/v1/plugin/IonReporterUploader/extend/wValidateUserInput/";
	$.ajax({
  			type: 'POST',
  			url: url + "?format=json&id="+accountId,
  			data: JSON.stringify(postData["userInput"]),
  			success: function(data){
				var results = data;
				var error_messages = [];
				var warning_messages = [];
				$.each(results["validationResults"], function(k, v){
					if (typeof v["errors"] != 'undefined' && v["errors"].length > 0) {
						$.each(v["errors"], function(i){
							error_messages.push("IonReporter:ERROR:Row" + v["row"] + ":" + v["errors"][i]);	
						});
					}
					if (typeof v["warnings"] != 'undefined' && v["warnings"].length > 0) {
						$.each(v["warnings"], function(i){
							warning_messages.push("IonReporter:WARNING:Row" + v["row"] + ":" + v["warnings"][i]);	
						});
					}
				});
	
				if (error_messages.length == 0 && warning_messages.length == 0) {
					$form.unbind("submit");
                	$form.submit();
                	return;
				}
				else if (warning_messages.length > 0 || error_messages.length > 0) {

					$.each(error_messages, function(i){
						var message = error_messages[i];
						var $div_error = $("<div></div>", {"style" : "color:red;font-weight:bold;margin-bottom:20px;"});
						$div_error.html(message+"<br/>");
						$div.append($div_error);
					});
					$.each(warning_messages, function(i){
						var message = warning_messages[i];
						var $div_error = $("<div></div>", {"style" : "color:red;font-weight:bold;"});
						$div_error.html(message+"<br/>");
						$div.append($div_error);
					});
				}
				$.unblockUI();
				show_apprise($form, results["advices"]["onTooManyErrors"]);
				$("html, body").animate({ scrollTop: 0 }, "slow");
  			},
  			dataType: "json",
  			async: true
	});
}

function validate_user_input_from_iru($form, accountId, accountName, userInputInfoDict) {

	var $div = $("#error");
	$div.html('');

	var url = "/rundb/api/v1/plugin/IonReporterUploader/extend/validateUserInput/";
	var data = {"userInput" : userInputInfoDict};

	console.log("iru_validation.validate_user_input_from_iru() userInputInfoDict=", userInputInfoDict);
	
	if (data["userInput"]["userInputInfo"].length == 0) {
		$div.html("You must enter at least one sample name");
		$.unblockUI();
		$("html, body").animate({ scrollTop: 0 }, "slow");
		return;
	} else {
		$div.html('');
	}
	call_validation_api($form, $div, data, accountId);
}

function get_user_input_info_from_ui(accountId, accountName, userInput) {
	var userInputInfo = {"userInputInfo" : [], "accountId" : accountId, "accountName" : accountName, "isVariantCallerSelected":userInput.is_variantCaller_enabled, "isVariantCallerConfigured": userInput.is_variantCaller_configured};
	var samplesTable = JSON.parse($('#samplesTable').val());
	for (i = 0; i < samplesTable.length; i++) {
		var row = samplesTable[i]
		var dict = {};
		dict["sample"] = row["sampleName"];
		dict["row"] = (i+1).toString();
		dict["Workflow"] = row["irWorkflow"];
		dict["Gender"] = row["irGender"];
		dict["nucleotideType"] = row["nucleotideType"];
		dict["Relation"] = row["irRelationshipType"];
		dict["RelationRole"] = row["irRelationRole"];
		dict["cancerType"] = row["ircancerType"];
		dict["cellularityPct"] = row["ircellularityPct"];
		dict["biopsyDays"] = row["irbiopsyDays"];
		dict["coupleID"] = row["ircoupleID"];
		dict["embryoID"] = row["irembryoID"];		
		dict["setid"] = row["irSetID"];
		userInputInfo["userInputInfo"].push(dict);
	}
	return userInputInfo;
}

$(document).ready(function(){

	$("form").submit(function(e){
	    updateSamplesTable();
	    
		var $div = $("#error");
		$div.html('');
        
        if ($("input[name=irDown]").val() == "1")
            return true;

        if (!USERINPUT.validate) {
            return true;
        } else {
            USERINPUT.validate = USERINPUT.is_by_sample;
        }
        
        $.blockUI();

        if ((USERINPUT.account_id != "0") && (USERINPUT.account_id != "-1")) {
        	var $rows = $("#chipsets tbody tr");;
        	var badRelation = false;   
        	var counter = 1; 
        	$.each($rows, function(i){
            	var $tr = $(this);            	
            	if ($tr.find(".irSampleName").val().length > 0 && ($tr.find(".irRelationRole").val() == null)) {            		
                	badRelation = true;
                	return false;            		
            	}
            	if ($tr.find(".irSampleName").val().length > 0 && $tr.find(".irRelationRole").val().length == 0 && $tr.find(".irWorkflow").val() != 'Upload Only') {
                	badRelation = true;
                	return false;
            	}
            	counter++;
        	});
        
        	if (badRelation){$div.text("Relation on row " + counter + " cannot be blank");$.unblockUI();return false;}
        	else {$div.text("");}

        	validate_user_input_from_iru($(this), USERINPUT.account_id, USERINPUT.account_name, get_user_input_info_from_ui(USERINPUT.account_id, USERINPUT.account_name, USERINPUT));
        	return false;
   		} else {
   			return true;
   		}
        return false;
    	
     });
});
