
$.getScript("../Scripts/LoginScript.js", function () {
    particlesJS('particles-js',
      {
          "particles": {
              "number": {
                  "value": 80,
                  "density": {
                      "enable": true,
                      "value_area": 800
                  }
              },
              "color": {
                  "value": "#ffffff"
              },
              "shape": {
                  "type": "circle",
                  "stroke": {
                      "width": 0,
                      "color": "#000000"
                  },
                  "polygon": {
                      "nb_sides": 5
                  },
                  "image": {
                      "width": 100,
                      "height": 100
                  }
              },
              "opacity": {
                  "value": 0.5,
                  "random": false,
                  "anim": {
                      "enable": false,
                      "speed": 1,
                      "opacity_min": 0.1,
                      "sync": false
                  }
              },
              "size": {
                  "value": 5,
                  "random": true,
                  "anim": {
                      "enable": false,
                      "speed": 40,
                      "size_min": 0.1,
                      "sync": false
                  }
              },
              "line_linked": {
                  "enable": true,
                  "distance": 150,
                  "color": "#ffffff",
                  "opacity": 0.4,
                  "width": 1
              },
              "move": {
                  "enable": true,
                  "speed": 6,
                  "direction": "none",
                  "random": false,
                  "straight": false,
                  "out_mode": "out",
                  "attract": {
                      "enable": false,
                      "rotateX": 600,
                      "rotateY": 1200
                  }
              }
          },
          "interactivity": {
              "detect_on": "canvas",
              "events": {
                  "onhover": {
                      "enable": true,
                      "mode": "repulse"
                  },
                  "onclick": {
                      "enable": true,
                      "mode": "push"
                  },
                  "resize": true
              },
              "modes": {
                  "grab": {
                      "distance": 400,
                      "line_linked": {
                          "opacity": 1
                      }
                  },
                  "bubble": {
                      "distance": 400,
                      "size": 40,
                      "duration": 2,
                      "opacity": 8,
                      "speed": 3
                  },
                  "repulse": {
                      "distance": 200
                  },
                  "push": {
                      "particles_nb": 4
                  },
                  "remove": {
                      "particles_nb": 2
                  }
              }
          },
          "retina_detect": true,
          "config_demo": {
              "hide_card": false,
              "background_color": "#b61924",
              "background_image": "",
              "background_position": "50% 50%",
              "background_repeat": "no-repeat",
              "background_size": "cover"
          }
      }
    );

});

$(document).ready(function () {
    $("#loginpage").keypress(function (e) {
        if (e.which == 13) {
            Login();
        }
    });
})
function Login() {
    debugger;
    if ($('#txtUsername').val() == '') {
        //$("#txtUsername").notify('Pleasse Enter Username',{ position:"right" });

    }
    if ($('#txtPassword').val() == '') {
        $("#txtPassword").notify('Please Enter Password', { position: "right" });
        return;
    }


    var Login = {
        "Username": $('#txtUsername').val(),
        "Password": $('#txtPassword').val(),      
    };

    var obji = { value: Login }
    debugger;
    $.ajax({
        type: "POST",
        url: "/items/UserLogin",
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {
            debugger;
            if (result.Message == "Success") {

                if (result.RoleID == "6") { // if BranchReservation Role
                    window.location.href = '/BranchReservation/IndexNew';
                }
                else if (result.RoleID == "5") { // if BranchReservation Role
                    window.location.href = '/SlideShow/SlideShows';
                }
                else {
                    //window.location.href = '/items/items/';
                    window.location.href = '/Category/Index';

                }
            }
            else if (result.Message == "Fail") {
                alert("Invalid Username or Password. Please Try Again")
            }
        }
    })
}


