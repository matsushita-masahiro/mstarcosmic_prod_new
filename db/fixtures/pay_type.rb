
PayType.delete_all
PayType.seed(:id,
# 管理者
  {:id => 1, :user_type_id => 1, :pay_name => "管理者",               :price => 0 },
# 会員
  {:id => 2, :user_type_id => 2, :pay_name => "会員(初回)",         :price => 10000,
   :paypal_form => "<form action='https://www.paypal.com/cgi-bin/webscr' method='post' target='_top'>
<input type='hidden' name='cmd' value='_s-xclick'>
<input type='hidden' name='hosted_button_id' value='EHSFQDDBBE5XA'>
<input type='image' src='https://www.paypalobjects.com/ja_JP/JP/i/btn/btn_buynowCC_LG.gif' border='0' name='submit' alt='PayPal - オンラインでより安全・簡単にお支払い'>
<img alt='' border='0' src='https://www.paypalobjects.com/ja_JP/i/scr/pixel.gif' width='1' height='1'>
</form>"},
  {:id => 3, :user_type_id => 2, :pay_name => "会員(1回券)",       :price => 9000,
  :paypal_form => "<form action='https://www.paypal.com/cgi-bin/webscr' method='post' target='_top'>
<input type='hidden' name='cmd' value='_s-xclick'>
<input type='hidden' name='hosted_button_id' value='WRPBH6YRSQTKN'>
<input type='image' src='https://www.paypalobjects.com/ja_JP/JP/i/btn/btn_buynowCC_LG.gif' border='0' name='submit' alt='PayPal - オンラインでより安全・簡単にお支払い'>
<img alt='' border='0' src='https://www.paypalobjects.com/ja_JP/i/scr/pixel.gif' width='1' height='1'>
</form>"},
  {:id => 4, :user_type_id => 2, :pay_name => "会員(回数券11枚)",   :price => 87000,
  :paypal_form => "<form action='https://www.paypal.com/cgi-bin/webscr' method='post' target='_top'>
<input type='hidden' name='cmd' value='_s-xclick'>
<input type='hidden' name='hosted_button_id' value='HTJTB45ETH5TW'>
<input type='image' src='https://www.paypalobjects.com/ja_JP/JP/i/btn/btn_buynowCC_LG.gif' border='0' name='submit' alt='PayPal - オンラインでより安全・簡単にお支払い'>
<img alt='' border='0' src='https://www.paypalobjects.com/ja_JP/i/scr/pixel.gif' width='1' height='1'>
</form>"},  
  {:id => 5, :user_type_id => 2, :pay_name => "病人(5回券/月)",     :price => 30000,
  :paypal_form => "<form action='https://www.paypal.com/cgi-bin/webscr' method='post' target='_top'>
<input type='hidden' name='cmd' value='_s-xclick'>
<input type='hidden' name='hosted_button_id' value='594PREZS3KEXE'>
<input type='image' src='https://www.paypalobjects.com/ja_JP/JP/i/btn/btn_buynowCC_LG.gif' border='0' name='submit' alt='PayPal - オンラインでより安全・簡単にお支払い'>
<img alt='' border='0' src='https://www.paypalobjects.com/ja_JP/i/scr/pixel.gif' width='1' height='1'>
</form>"},
# 一般
  {:id => 6, :user_type_id => 3, :pay_name => "一般(初回)",         :price => 12000,
  :paypal_form => "<form action='https://www.paypal.com/cgi-bin/webscr' method='post' target='_top'>
<input type='hidden' name='cmd' value='_s-xclick'>
<input type='hidden' name='hosted_button_id' value='4JEREQJNCWC4Y'>
<input type='image' src='https://www.paypalobjects.com/ja_JP/JP/i/btn/btn_buynowCC_LG.gif' border='0' name='submit' alt='PayPal - オンラインでより安全・簡単にお支払い'>
<img alt='' border='0' src='https://www.paypalobjects.com/ja_JP/i/scr/pixel.gif' width='1' height='1'>
</form>"},
  {:id => 7, :user_type_id => 3, :pay_name => "一般(1回券)",       :price => 10000,
  :paypal_form => "<form action='https://www.paypal.com/cgi-bin/webscr' method='post' target='_top'>
<input type='hidden' name='cmd' value='_s-xclick'>
<input type='hidden' name='hosted_button_id' value='LK6Q3X4CGK6WW'>
<input type='image' src='https://www.paypalobjects.com/ja_JP/JP/i/btn/btn_buynowCC_LG.gif' border='0' name='submit' alt='PayPal - オンラインでより安全・簡単にお支払い'>
<img alt='' border='0' src='https://www.paypalobjects.com/ja_JP/i/scr/pixel.gif' width='1' height='1'>
</form>"},
  {:id => 8, :user_type_id => 3, :pay_name => "一般(回数券11枚)",   :price => 100000,
  :paypal_form => "<form action='https://www.paypal.com/cgi-bin/webscr' method='post' target='_top'>
<input type='hidden' name='cmd' value='_s-xclick'>
<input type='hidden' name='hosted_button_id' value='N7GWPQ9E6P3VQ'>
<input type='image' src='https://www.paypalobjects.com/ja_JP/JP/i/btn/btn_buynowCC_LG.gif' border='0' name='submit' alt='PayPal - オンラインでより安全・簡単にお支払い'>
<img alt='' border='0' src='https://www.paypalobjects.com/ja_JP/i/scr/pixel.gif' width='1' height='1'>
</form>"},  
  {:id => 9, :user_type_id => 3, :pay_name => "病人(5回券/月)",     :price => 35000,
  :paypal_form => "<form action='https://www.paypal.com/cgi-bin/webscr' method='post' target='_top'>
<input type='hidden' name='cmd' value='_s-xclick'>
<input type='hidden' name='hosted_button_id' value='2FTBPU5555U5L'>
<input type='image' src='https://www.paypalobjects.com/ja_JP/JP/i/btn/btn_buynowCC_LG.gif' border='0' name='submit' alt='PayPal - オンラインでより安全・簡単にお支払い'>
<img alt='' border='0' src='https://www.paypalobjects.com/ja_JP/i/scr/pixel.gif' width='1' height='1'>
</form>"},
# 代理店A
  {:id => 10, :user_type_id => 4, :pay_name => "代理店(初回)",       :price => 22000,
  :paypal_form => "<form action='https://www.paypal.com/cgi-bin/webscr' method='post' target='_top'>
<input type='hidden' name='cmd' value='_s-xclick'>
<input type='hidden' name='hosted_button_id' value='UHZU8T2EFRJKA'>
<input type='image' src='https://www.paypalobjects.com/ja_JP/JP/i/btn/btn_buynowCC_LG.gif' border='0' name='submit' alt='PayPal - オンラインでより安全・簡単にお支払い'>
<img alt='' border='0' src='https://www.paypalobjects.com/ja_JP/i/scr/pixel.gif' width='1' height='1'>
</form>"},  
  {:id => 11, :user_type_id => 4, :pay_name => "代理店(1回券)",     :price => 20000,
  :paypal_form => "<form action='https://www.paypal.com/cgi-bin/webscr' method='post' target='_top'>
<input type='hidden' name='cmd' value='_s-xclick'>
<input type='hidden' name='hosted_button_id' value='23LQWWPER3WR6'>
<input type='image' src='https://www.paypalobjects.com/ja_JP/JP/i/btn/btn_buynowCC_LG.gif' border='0' name='submit' alt='PayPal - オンラインでより安全・簡単にお支払い'>
<img alt='' border='0' src='https://www.paypalobjects.com/ja_JP/i/scr/pixel.gif' width='1' height='1'>
</form>"},
  {:id => 12, :user_type_id => 4, :pay_name => "代理店(回数券11枚)", :price => 180000,
  :paypal_form => "<form action='https://www.paypal.com/cgi-bin/webscr' method='post' target='_top'>
<input type='hidden' name='cmd' value='_s-xclick'>
<input type='hidden' name='hosted_button_id' value='GDUYXUT75D7V4'>
<input type='image' src='https://www.paypalobjects.com/ja_JP/JP/i/btn/btn_buynowCC_LG.gif' border='0' name='submit' alt='PayPal - オンラインでより安全・簡単にお支払い'>
<img alt='' border='0' src='https://www.paypalobjects.com/ja_JP/i/scr/pixel.gif' width='1' height='1'>
</form>"},
  {:id => 13, :user_type_id => 4, :pay_name => "代理店(回数券5枚)", :price => 87000,
  :paypal_form => "<form action='https://www.paypal.com/cgi-bin/webscr' method='post' target='_top'>
<input type='hidden' name='cmd' value='_s-xclick'>
<input type='hidden' name='hosted_button_id' value='QKHZCBB78K9NE'>
<input type='image' src='https://www.paypalobjects.com/ja_JP/JP/i/btn/btn_buynowCC_LG.gif' border='0' name='submit' alt='PayPal - オンラインでより安全・簡単にお支払い'>
<img alt='' border='0' src='https://www.paypalobjects.com/ja_JP/i/scr/pixel.gif' width='1' height='1'>
</form>"},
# 代理店B
  {:id => 14, :user_type_id => 5, :pay_name => "代理店(初回)",       :price => 22000,
  :paypal_form => "<form action='https://www.paypal.com/cgi-bin/webscr' method='post' target='_top'>
<input type='hidden' name='cmd' value='_s-xclick'>
<input type='hidden' name='hosted_button_id' value='UHZU8T2EFRJKA'>
<input type='image' src='https://www.paypalobjects.com/ja_JP/JP/i/btn/btn_buynowCC_LG.gif' border='0' name='submit' alt='PayPal - オンラインでより安全・簡単にお支払い'>
<img alt='' border='0' src='https://www.paypalobjects.com/ja_JP/i/scr/pixel.gif' width='1' height='1'>
</form>"},  
  {:id => 15, :user_type_id => 5, :pay_name => "代理店(1回券)",     :price => 20000,
  :paypal_form => "<form action='https://www.paypal.com/cgi-bin/webscr' method='post' target='_top'>
<input type='hidden' name='cmd' value='_s-xclick'>
<input type='hidden' name='hosted_button_id' value='23LQWWPER3WR6'>
<input type='image' src='https://www.paypalobjects.com/ja_JP/JP/i/btn/btn_buynowCC_LG.gif' border='0' name='submit' alt='PayPal - オンラインでより安全・簡単にお支払い'>
<img alt='' border='0' src='https://www.paypalobjects.com/ja_JP/i/scr/pixel.gif' width='1' height='1'>
</form>"},
  {:id => 16, :user_type_id => 5, :pay_name => "代理店(回数券11枚)", :price => 180000,
  :paypal_form => "<form action='https://www.paypal.com/cgi-bin/webscr' method='post' target='_top'>
<input type='hidden' name='cmd' value='_s-xclick'>
<input type='hidden' name='hosted_button_id' value='GDUYXUT75D7V4'>
<input type='image' src='https://www.paypalobjects.com/ja_JP/JP/i/btn/btn_buynowCC_LG.gif' border='0' name='submit' alt='PayPal - オンラインでより安全・簡単にお支払い'>
<img alt='' border='0' src='https://www.paypalobjects.com/ja_JP/i/scr/pixel.gif' width='1' height='1'>
</form>"},
  {:id => 17, :user_type_id => 5, :pay_name => "代理店(回数券5枚)", :price => 87000,
  :paypal_form => "<form action='https://www.paypal.com/cgi-bin/webscr' method='post' target='_top'>
<input type='hidden' name='cmd' value='_s-xclick'>
<input type='hidden' name='hosted_button_id' value='QKHZCBB78K9NE'>
<input type='image' src='https://www.paypalobjects.com/ja_JP/JP/i/btn/btn_buynowCC_LG.gif' border='0' name='submit' alt='PayPal - オンラインでより安全・簡単にお支払い'>
<img alt='' border='0' src='https://www.paypalobjects.com/ja_JP/i/scr/pixel.gif' width='1' height='1'>
</form>"},
# 特別会員
  {:id => 18, :user_type_id => 6, :pay_name => "特別会員", :price => 0,
  :paypal_form => "<p class='text-danger h3'>特別会員です、お支払いの必要はありません</p>"},
# その他
  {:id => 19, :user_type_id => 7, :pay_name => "その他", :price => 9000,
  :paypal_form => "<form action='https://www.paypal.com/cgi-bin/webscr' method='post' target='_top'>
<input type='hidden' name='cmd' value='_s-xclick'>
<input type='hidden' name='hosted_button_id' value='XNGP8VRZ2ZLX6'>
<input type='image' src='https://www.paypalobjects.com/ja_JP/JP/i/btn/btn_buynowCC_LG.gif' border='0' name='submit' alt='PayPal - オンラインでより安全・簡単にお支払い'>
<img alt='' border='0' src='https://www.paypalobjects.com/ja_JP/i/scr/pixel.gif' width='1' height='1'>
</form>"},
# テスト
  {:id => 99, :user_type_id => 99,  :pay_name => "テスト", :price => 1,
  :paypal_form => "<form action='https://www.paypal.com/cgi-bin/webscr' method='post' target='_top'>
<input type='hidden' name='cmd' value='_s-xclick'>
<input type='hidden' name='hosted_button_id' value='3XKANX3H3NJ8S'>
<input type='image' src='https://www.paypalobjects.com/ja_JP/JP/i/btn/btn_buynowCC_LG.gif' border='0' name='submit' alt='PayPal - オンラインでより安全・簡単にお支払い'>
<img alt='' border='0' src='https://www.paypalobjects.com/ja_JP/i/scr/pixel.gif' width='1' height='1'>
</form>"}
)
