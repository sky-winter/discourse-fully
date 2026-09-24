import Component from '@glimmer/component';
import { action } from '@ember/object';
import { schedule } from '@ember/runloop';
import DButton from 'discourse/components/d-button';
import DModal from 'discourse/components/d-modal';
import { apiInitializer } from 'discourse/lib/api';

const isLogoutKey = 'is_logout';
const personalInfoAgreedKey = 'personal_info_agreed';
const testEnv = '.test.osinfra.cn';

function getCookie(name) {
  const matchField = name + '=';
  const ca = document.cookie.split(';');
  for (let i = 0; i < ca.length; i++) {
    const c = ca[i].trim();
    if (c.indexOf(matchField) === 0) {
      return c.substring(matchField.length, c.length);
    }
  }
  return '';
}

const localeCookieName = 'locale';

// 英文 locale 判断：cookie 不存在（如中文时）回退到 <html lang> 判断
function isEnglishLocale() {
  const cookieLocale = getCookie(localeCookieName).toLowerCase();
  const lang =
    cookieLocale ||
    (document.documentElement.getAttribute('lang') || '').toLowerCase();
  return lang.startsWith('en');
}

const personalInfoTexts = {
  zh: {
    title: '跨境说明',
    contentBefore:
      '当您使用论坛服务时，我们将您的论坛互动信息存储在中国香港特别行政区，用于您的交流互动。详细信息请查看：',
    privacyLabel: '《隐私声明》',
    contentAfter: '。如您拒绝，将影响论坛功能的正常使用。',
    confirm: '同意',
    cancel: '取消',
  },
  en: {
    title: 'Cross-border Statement',
    contentBefore:
      'When you use the forum services, we store your forum interaction information in the Hong Kong Special Administrative Region of China for communication purposes. For details, please refer to the ',
    privacyLabel: 'Privacy Statement',
    contentAfter: '. If you refuse, the normal use of the forum functions will be affected.',
    confirm: 'Ok',
    cancel: 'Cancel',
  },
};

// 同步官网登录
function syncLoginStatus() {
  const userToken = getCookie('_U_T_');
  if (userToken) {
    const loginDom = document.querySelector(
      '.header-buttons .auth-buttons .login-button'
    );
    // 找到登录dom元素表示没有登录，手动触发一次点击事件
    if (loginDom) {
      loginDom.click();
    }
  }
}

// 论坛登出，调取官网接口，退出官网
async function logoutForum() {
  const curUrl = new URL(window.location.href);
  if (curUrl.href.includes(testEnv)) {
    await fetch('/gauss-logout-test', {
      method: 'GET',
      headers: { 'Content-Type': 'application/json' },
    }).then((res) => {
      return res.json();
    });
  } else {
    await fetch('/gauss-logout', {
      method: 'GET',
      headers: { 'Content-Type': 'application/json' },
    }).then((res) => {
      return res.json();
    });
  }
}

// 隐私声明链接：测试环境与生产环境地址不同，语言跟随当前 locale
function getPrivacyUrl() {
  const langPath = isEnglishLocale() ? 'en' : 'zh';
  const curUrl = new URL(window.location.href);
  if (curUrl.href.includes(testEnv)) {
    return `https://opengauss.test.osinfra.cn/${langPath}/privacy`;
  }
  return `https://opengauss.org/${langPath}/privacy`;
}

// 个人信息弹窗，同意后方可继续使用论坛，取消退出登录
class PersonalInfoModal extends Component {
  get texts() {
    return isEnglishLocale() ? personalInfoTexts.en : personalInfoTexts.zh;
  }

  get privacyUrl() {
    return getPrivacyUrl();
  }

  @action
  handleConfirm() {
    localStorage.setItem(personalInfoAgreedKey, 'true');
    this.args.closeModal();
  }

  @action
  async handleCancel() {
    this.args.closeModal();
    await logoutForum();
    window.location.href = '/';
  }

  <template>
    <DModal
      @title={{this.texts.title}}
      @closeModal={{@closeModal}}
      @dismissable={{false}}
    >
      <:body>
        <p>
          {{this.texts.contentBefore}}<a
            class="personal-info-link"
            href={{this.privacyUrl}}
            target="_blank"
            rel="noopener noreferrer"
          >{{this.texts.privacyLabel}}</a>{{this.texts.contentAfter}}
        </p>
      </:body>
      <:footer>
        <DButton
          class="personal-info-btn"
          @translatedLabel={{this.texts.confirm}}
          @action={{this.handleConfirm}}
        />
        <DButton
          class="personal-info-btn"
          @translatedLabel={{this.texts.cancel}}
          @action={{this.handleCancel}}
        />
      </:footer>
    </DModal>
  </template>
}

export default apiInitializer('1.34.0', (api) => {
  api.renderInOutlet(
    "home-logo-contents",
    <template>
      <a class="forum-logo logo_pc" href="/">
      </a>
      <a class="forum-logo logo_mb" href="/">
      </a>
      <span class="divid"></span>
      <a
        class="website-logo lang-zh"
        href="https://opengauss.org/zh/"
        target="_blank"
      >
      </a>
      <a
        class="website-logo lang-en"
        href="https://opengauss.org/en/"
        target="_blank"
      >
      </a>
    </template>
  );

  let isUserFirstListen = false;
  let isAvatarFirstListen = false;
  let isQuitFirstListen = false;

  const modal = api.container.lookup('service:modal');

  api.onAppEvent('page:changed', async () => {
    const isLogout = sessionStorage.getItem(isLogoutKey);

    if (isLogout === null) {
      // 同步官网登录
      syncLoginStatus();
    }

    // 根据当前登录用户判断：未同意声明时，每次进入/刷新页面都立即弹出弹窗
    // 弹窗为强制门禁（不可关闭），点击同意后不再弹出，点击取消则退出登录
    const user = api.getCurrentUser();
    if (!user) {
      localStorage.removeItem(personalInfoAgreedKey);
    } else if (!localStorage.getItem(personalInfoAgreedKey)) {
      // 延后到渲染完成再弹窗，避免应用启动阶段弹层未就绪导致层级/显示异常
      schedule('afterRender', () => {
        // 弹窗已在页面中时不再重复弹出
        if (!document.querySelector('.d-modal .personal-info-link')) {
          modal.show(PersonalInfoModal);
        }
      });
    }

    if (isLogout) {
      sessionStorage.removeItem(isLogoutKey);
      await logoutForum();
    } else{
        // 论坛登出，官网同步登出
        const userBtn = document.querySelector('.d-header-icons .current-user .avatar');
        // 未登录时 userBtn 不存在，此时不置标记，等登录后的 page:changed 再重新绑定
        if (!isUserFirstListen && userBtn) {
          isUserFirstListen = true;
          userBtn.addEventListener("click", () => {
            if (!isAvatarFirstListen) {
              isAvatarFirstListen = true;
              requestAnimationFrame(() => {
                const avatarIcon = document.querySelector('.user-menu-dropdown-wrapper .bottom-tabs .user-menu-tab');
                avatarIcon.addEventListener("click", () => {
                  if (!isQuitFirstListen) {
                    isQuitFirstListen = true;
                    const logoutBtn = document.querySelector('.user-menu .quick-access-panel .logout button');
                    if (logoutBtn) {
                      logoutBtn.addEventListener("click", () => {
                        sessionStorage.setItem(isLogoutKey, true);
                      });
                    }
                  }
              });
            });
          }
        });
      }
    }
  });
});
