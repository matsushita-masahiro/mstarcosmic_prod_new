document.addEventListener("turbo:load", function() {

          console.log("================== schedule check 通過");
           
          // 全選択 --------------------------------------------------------------
          
          $('#all_check').on('click', function() {
            $("input[name='staff[schedule][]").prop('checked', this.checked);
            // console.log("================== all check clicked");
          });
          
          
          // 「全選択」以外のチェックボックスがクリックされたら、
          $("input[name='user[schedule][]']").on('click', function() {
            if ($('#boxes :checked').length == $('#boxes :input').length) {
              // 全てのチェックボックスにチェックが入っていたら、「全選択」 = checked
              $('#all_check').prop('checked', true);
            } else {
              // 1つでもチェックが入っていたら、「全選択」 = checked
              $('#all_check').prop('checked', false);
            }
          });
          
          
          
          // １日選択 --------------------------------------------------------------
          
          
          // 1
          $('#day_allChecked_0').on('click', function() {
            $("input[class='day_check_0']").prop('checked', this.checked);
          });
          
          // 2
          $('#day_allChecked_1').on('click', function() {
            $("input[class='day_check_1']").prop('checked', this.checked);
          });          
          
          // 3
          $('#day_allChecked_2').on('click', function() {
            $("input[class='day_check_2']").prop('checked', this.checked);
          });
          
          // 4
          $('#day_allChecked_3').on('click', function() {
            $("input[class='day_check_3']").prop('checked', this.checked);
          });  
          
          // 5
          $('#day_allChecked_4').on('click', function() {
            $("input[class='day_check_4']").prop('checked', this.checked);
          });          
          
          // 6
          $('#day_allChecked_5').on('click', function() {
            $("input[class='day_check_5']").prop('checked', this.checked);
          });
          
          // 7
          $('#day_allChecked_6').on('click', function() {
            $("input[class='day_check_6']").prop('checked', this.checked);
          });  
});