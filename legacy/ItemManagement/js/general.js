$(document).ready(function () {
	//Prevent Page Reload on all # links
	$("a[href='#']").click(function (e) {
		e.preventDefault();
	});

	$('.card-primary .btn-plus').on('click', function () {
		$(".top-header .cart").addClass('add');
		setTimeout(function () {
			$('.top-header .cart').removeClass('add');
		}, 800);
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

	$('#scrollpage').click(function (ev) {
		ev.preventDefault();
		$(".main-content").animate({ scrollTop: '+=350px' }, 600);
	})

	$(window).scroll(function () {
		if ($(this).scrollTop() > 600) {
			$('#scrollpage').fadeIn();
		}
		else {
			$('#scrollpage').fadeOut();
		}
	})

	// // On scroll Add Class
	$(".product-details-inner").scroll(function (e) {
		if ($(".product-details-inner").scrollTop() >= 20) {
			$(".product-details-inner").addClass('page-scrolled');
		} else {
			$(".product-details-inner").removeClass('page-scrolled');
		}
	});

	// Selectpicker ===========================
	$('.selectpicker').selectpicker({
		rtl: true
	});
	// Selectpicker end===========================

	// track-ouder ===========================
	$('.btn-map-view').click(function (e) {
		e.preventDefault();
		$(".track-ouder").addClass("active");
		$(".track-block").slideUp();
	})
	$('.btn-track-view').click(function (e) {
		e.preventDefault();
		$(".track-ouder").removeClass("active");
		$(".track-block").slideDown();
	})

	// Datepicker ===========================

	//$('.datepicker').datepicker({
	//	autoclose: true,
	//	format: "dd M yyyy",
	//	ignoreReadonly: true,
	//	inline: true,
	//	rtl: true
	//});
	// Datepicker ===========================

	$('.owl-carousel').owlCarousel({
		margin: 10,
		dots: false,
		rtl: true,
		responsive: {
			0: {
				items: 3
			},
			420: {
				items: 4
			},
			575: {
				items: 5
			},
			768: {
				items: 6
			},
			992: {
				items: 4
			},
		}

	})

	// Category Page height

	$('#en').click(function () {
		$(this).removeClass("d-block").addClass("d-none");
		$('#ar').removeClass("d-none").addClass("d-block");
		$("body").addClass("rtl");
	});

	$('#ar').click(function () {
		$(this).removeClass("d-block").addClass("d-none");
		$('#en').removeClass("d-none").addClass("d-block");
		$("body").removeClass("rtl");
	});



	if ($(window).width() < 991) {
		var winh = $(window).innerHeight();
		var headerh = $(".header").innerHeight();
		var titleh = $(".item-list-title").innerHeight();
		var totaMin = headerh + titleh;
		var winmh = winh - totaMin + 15;
		//$(".main-content").css("max-height", winmh);
		//when one or two items then background color not display proper 
		$(".main-content").height("100%");
	} else {
		$(".main-content").height("100%");
	}


	$(window).resize(function () {
		if ($(window).width() < 991) {
			var winh = $(window).innerHeight();
			var headerh = $(".header").innerHeight();
			var titleh = $(".item-list-title").innerHeight();
			var totaMin = headerh + titleh;
			var winmh = winh - totaMin + 15;
			//$(".main-content").css("max-height", winmh);
			//when one or two items then background color not display proper 
			$(".main-content").height("100%");
		} else {
			$(".main-content").height("100%");
		}
	});

});
