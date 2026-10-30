$(document).ready(function() {
	//Prevent Page Reload on all # links
	$("body").on("click","a[href='#']", function(e){
		e.preventDefault();
	});

	//placeholder
	$("[placeholder]").each(function () {
		$(this).attr("data-placeholder", this.placeholder);
		$(this).bind("focus", function () {
			this.placeholder = '';
		});
		$(this).bind("blur", function () {
			this.placeholder = $(this).attr("data-placeholder");
		});
	});
	
	// On scroll Add Class
	$(window).scroll(function(e) {
		if($(window).scrollTop() > 200){
			$(".wrapper").addClass('page-scrolled');
		}
		else{
			$(".wrapper").removeClass('page-scrolled');
		}
	});	

	// Footer margin set for stick to bottom
	function footerAdj(){
		var footerH = $(".footer").innerHeight();
		$(".footer").css({ "margin-top": -footerH});
		$(".main-content").css({ "padding-bottom": footerH});
	};
	footerAdj();
	$(window).resize(function() {
		footerAdj();		
	});

	// Add remove class when window resize finished
	var $resizeTimer;
	$(window).on("resize", function(e) {
		if(!$("body").hasClass("window-resizing")){
			$("body").addClass("window-resizing");
		}
		clearTimeout($resizeTimer);
		$resizeTimer = setTimeout(function() {    
			$("body").removeClass("window-resizing");
		}, 250);
	});	

	// Add new js functions here -----------------------------------------------------------------
	//if($(window).innerWidth() > 767){
	//	$('#item-management-list').gridstrap();
	//}
	//$(window).on("resize", function(e) {
	//	if($(window).innerWidth() > 767){
	//		$('#item-management-list').gridstrap();
	//	}
	//});

    // uploadBtn
    //$('.custom-file-input').on('change', function () {
    //    //get the file name
    //    debugger;
    //    var fileName = $(this).val();

    //    var fileNameIndex = fileName.lastIndexOf("\\") + 1;
    //    fileName = fileName.substr(fileNameIndex);
    //    //replace the "Choose a file" label
    //    $(this).next('.custom-file-label').html(fileName);
    //});

// MultiSelect
	$(".MultiSelect").bsMultiSelect();

    (function () {
        'use strict';
        window.addEventListener('load', function () {
            // Fetch all the forms we want to apply custom Bootstrap validation styles to
            var forms = document.getElementsByClassName('needs-validation');
            // Loop over them and prevent submission
            var validation = Array.prototype.filter.call(forms, function (form) {
                form.addEventListener('submit', function (event) {
                    if (form.checkValidity() === false) {
                        event.preventDefault();
                        event.stopPropagation();
                    }
                    form.classList.add('was-validated');
                }, false);
            });
        }, false);
    })();


// Don't add anything below this --------------------------------------------------------------
	// Add Class on Window Load
	$("body").addClass("page-loaded");
});