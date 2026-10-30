$(document).ready(function () {
   GetImageSlideShows()
})

var slideIndex = 0;
function GetImageSlideShows() {
    $.ajax({
        type: "POST",
        cache: false,
        url: "/items/GetWebImageSlideShow",
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {
            var ImageData = result.dtItems;
            var t = ""
            var j = ""
            for (var i = 0; i < ImageData.length; i++) {
              
 
t = t + '<div class="mySlides fade"><img src="../../images/webSlide/' + ImageData[i].IMAGENAME + '" style=" height: 100%"></div>  '
                j = j + '   <span class="dot"></span>'
            }
            $("#SlideshowImages").html(t);         
            showSlides();
            }        
    });
}

function plusDivs(n) {
    showDivs(slideIndex += n);
}

function showDivs(n) {
    var i;
    var x = document.getElementsByClassName("mySlides");
  
    if (n > x.length) { slideIndex = 1 }
    if (n < 1) { slideIndex = x.length }
    for (i = 0; i < x.length; i++) {
        x[i].style.display = "none";
    }  
    x[slideIndex - 1].style.display = "block";
 
}


function showSlides() {
    var i;
    var slides = document.getElementsByClassName("mySlides");

    for (i = 0; i < slides.length; i++) {
        slides[i].style.display = "none";
    }
    slideIndex++;
    if (slideIndex > slides.length) { slideIndex = 1 }    
    slides[slideIndex - 1].style.display = "block";  
    setTimeout(showSlides, 5000); // Change image every 2 seconds
}
